// Generate the Forever boss-name overlay from DBM's locale tables.
//
//   node tools/map-data/bosses-locales.mjs OpenMap/Data/Forever/Bosses.lua \
//     /path/to/DBM-Raids-Vanilla /path/to/DBM-Dungeons/DBM-Party-Vanilla/Shared \
//     /path/to/DBM-Dungeons/DBM-Party-Vanilla/Classic \
//     /path/to/DBM-Dungeons/DBM-Party-Forever \
//     /path/to/DBM-Dungeons/DBM-Party-Vanilla/locale.generated.lua
//
// The DBM repositories are inputs rather than OpenMap dependencies. English remains in
// Data/Forever/Places.lua, and names DBM does not translate retain that English fallback.
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [out, raidsRoot, ...dungeonRoots] = process.argv.slice(2);
const localeNames = {
  enUS: "en", deDE: "de", esES: "es", esMX: "mx", frFR: "fr", itIT: "it",
  koKR: "kr", ptBR: "br", ruRU: "ru", zhCN: "cn", zhTW: "tw",
};
const locales = Object.keys(localeNames);

function allFiles(root) {
  if (statSync(root).isFile()) return [root];
  const files = [];
  for (const name of readdirSync(root)) {
    const path = join(root, name);
    if (statSync(path).isDirectory()) files.push(...allFiles(path));
    else if (name === "locale.generated.lua" || /^localization\.(?:en|br|cn|de|es|fr|it|kr|mx|ru|tw)\.lua$/.test(name)) files.push(path);
  }
  return files;
}

function luaUnescape(value) {
  return value.replace(/\\(["\\])/g, "$1");
}

function normalize(value) {
  return value.toLocaleLowerCase("en-US").replace(/[^a-z0-9]/g, "");
}

const byId = new Map();
function add(id, locale, value, kind) {
  if (!localeNames[locale] && !Object.values(localeNames).includes(locale)) return;
  const short = localeNames[locale] ?? locale;
  const key = `${kind}:${id}`;
  const record = byId.get(key) ?? {};
  record[short] = value;
  byId.set(key, record);
}

for (const { kind, root } of [
  { kind: "raid", root: raidsRoot },
  ...dungeonRoots.map((root) => ({ kind: "dungeon", root })),
].filter(({ root }) => root)) {
  for (const file of allFiles(root)) {
    const text = readFileSync(file, "utf8");
    const localization = file.match(/localization\.([^.]+)\.lua$/)?.[1];
    if (localization) {
      for (const part of text.split(/(?=L\s*=\s*DBM:GetModLocalization\()/).slice(1)) {
        const id = part.match(/DBM:GetModLocalization\((?:"([^"]+)"|(\d+))\)/);
        const name = part.match(/L:SetGeneralLocalization\s*\(?\s*\{[\s\S]*?\bname\s*=\s*"((?:\\.|[^"\\])*)"/)?.[1];
        if (id && name) add(id[1] ?? id[2], localization, luaUnescape(name), kind);
      }
      continue;
    }
    for (const block of text.split(/(?=if GetLocale\(\) == ")/)) {
      const locale = block.match(/^if GetLocale\(\) == "([^"]+)" then/)?.[1];
      if (!locale) continue;
      for (const [, id, value] of block.matchAll(/\[(\d+)\]\s*=\s*"((?:\\.|[^"\\])*)"/g)) {
        add(id, locale, luaUnescape(value), kind);
      }
    }
  }
}

const sourceByEnglish = { dungeon: new Map(), raid: new Map() };
for (const [key, record] of byId) {
  if (!record.en) continue;
  const name = normalize(record.en);
  const kind = key.slice(0, key.indexOf(":"));
  const values = sourceByEnglish[kind].get(name) ?? Object.fromEntries(Object.values(localeNames).map((locale) => [locale, new Set()]));
  for (const locale of Object.values(localeNames)) if (record[locale] && locale !== "en") values[locale].add(record[locale]);
  sourceByEnglish[kind].set(name, values);
}

// DBM keeps the original Blackfathom Deeps encounters in its raid locale table even though
// OpenMap lists the instance as a dungeon.  Try the instance's source first, then the other
// source, so those Vanilla encounters do not lose their translations.
const sourcesFor = (kind) => [sourceByEnglish[kind], sourceByEnglish[kind === "raid" ? "dungeon" : "raid"]];

const places = readFileSync("OpenMap/Data/Forever/Places.lua", "utf8");
const instanceSection = places.slice(places.indexOf("\tinstances = {"), places.indexOf("\tbosses = {"));
const raidMaps = new Set([...instanceSection.matchAll(/\{\s*(\d+),\s*"(?:[^"\\]|\\.)*",\s*true\b/g)].map((match) => match[1]));
const bossSection = places.slice(places.indexOf("\tbosses = {"), places.indexOf("\ttransports = {"));
const bosses = [...bossSection.matchAll(/\[(\d+)\]\s*=\s*\{([^}]*)\}/gs)].map((match) => ({
  id: Number(match[1]),
  names: [...match[2].matchAll(/"((?:\\.|[^"\\])*)"/g)].map((part) => luaUnescape(part[1])),
}));

const aliases = new Map([
  ["sneed", "sneedsshredder"],
  ["gizrultheslavener", "gizrul"],
  ["overlordramtusk", ["overloadramtusk", "warlordramtusk"]],
  ["warderstilgiss", "wardenstilgiss"],
  ["illyannaravenoak", "illyannaravensoak"],
  ["mordreshfireeye", "mordressfireeye"],
  ["amnennarthecoldbringer", "amnenarthecoldbringer"],
  ["kirtonos", "kirtonostheherald"],
  ["rasfrostwhisperer", "rasfrostwhisper"],
  ["shadowpriestsezzziz", "nekrumsezzziz"],
]);

// Some legacy encounters have no DBM localization block, but the client still has translated
// names. Keep this small fallback for names DBM does not publish.
const fallbackTranslations = {
  kormok: {
    de: "Kormok", es: "Kormok", mx: "Kormok", fr: "Kormok", it: "Kormok", br: "Kormok",
    ru: "Кормок", kr: "코르모크", cn: "库尔莫克", tw: "科爾莫克",
  },
  pusillin: {
    de: "Pusillin", es: "Pusillín", mx: "Pusillín", fr: "Pusillin", it: "Pusillin", br: "Pusillin",
    ru: "Пузиллин", kr: "푸실린", cn: "普希林", tw: "普希林",
  },
  blackguardswordsmith: {
    de: "Schwertschmied der schwarzen Wache", es: "Armero Guardia Negra", mx: "Armero Guardia Negra",
    fr: "Fabricant d'épées de la Garde noire", it: "Fabbro della Guardia Nera", br: "Cuteleiro da Guarda Negra",
    ru: "Оружейник Черной Стражи", kr: "검은호위대 검제작자", cn: "黑衣守卫铸剑师", tw: "黑衣守衛鑄劍師",
  },
  crimsonhammersmith: {
    de: "Purpurroter Hammerschmied", es: "Forjamartillos Carmesí", mx: "Forjador de martillos carmesí",
    fr: "Forgeur de marteaux cramoisi", it: "Crimson Hammersmith", br: "Forjador de Martelos Carmesim",
    ru: "Молотобоец из Багрового Легиона", kr: "진홍십자군 대장장이", cn: "红衣铸锤师", tw: "紅衣鑄錘師",
  },
  ezragrimm: {
    de: "Ezra Grimm", es: "Fras Siabi", mx: "Fras Siabi", fr: "Ezra Grimm", it: "Ezra Grimm", br: "Fras Siabi",
    ru: "Эзра Гримм", kr: "에즈라 그림", cn: "艾兹拉·格里姆", tw: "艾茲拉‧格里姆",
  },
  postmastermalown: {
    de: "Postmeister Malown", es: "Jefe de correos Gassol", mx: "Jefe de correos Gassol", fr: "Postier Malown",
    it: "Postino Malown", br: "Chefe do Correio Malown", ru: "Почтальон Мэлоун", kr: "우체국장 말로운",
    cn: "邮差马龙", tw: "郵差瑪羅恩",
  },
  skul: {
    de: "Skul", es: "Skul", mx: "Skul", fr: "Krân", it: "Kranio", br: "Kranio",
    ru: "Череп", kr: "스컬", cn: "斯库尔", tw: "斯庫爾",
  },
  stonespine: {
    de: "Steinbuckel", es: "Pidrespina", mx: "Pidrespina", fr: "Échine-de-pierre", it: "Spinapietra",
    br: "Petrespáduas", ru: "Каменный Гребень", kr: "뾰족바위", cn: "石脊", tw: "石脊",
  },
  princessmoirabronzebeard: {
    de: "Prinzessin Moira Bronzebart", es: "Princesa Moira Barbabronce", mx: "Princesa Moira Barbabronce",
    fr: "Princesse Moira Barbe-de-Bronze", it: "Principessa Moira Barbabronzea", br: "Princesa Moira Barbabronze",
    ru: "Принцесса Мойра Бронзобород", kr: "공주 모이라 브론즈비어드", cn: "铁炉堡公主茉艾拉·铜须", tw: "茉艾拉·銅鬚公主",
  },
  thevault: {
    de: "Der Tresorraum", es: "Cámara Negra", mx: "Cámara Negra", fr: "La Chambre forte", it: "The Vault",
    br: "Cofre Negro", ru: "Подземелье", kr: "검은 금고", cn: "黑色宝库", tw: "地窖",
  },
  ribblyscrewspigot: {
    de: "Ribbly Schraubstutz", es: "Ribbly Llavenrosca", mx: "Ribbly Llavenrosca", fr: "Ribbly Fermevanne",
    it: "Ribbly Giravite", br: "Ribas Parafuseta", ru: "Риббли Крутипроб", kr: "리블리 스크류스피곳",
    cn: "雷布里·斯库比格特", tw: "雷布里·斯庫比格特",
  },
};

const lua = (value) => `{ ${value.map((name) => JSON.stringify(name)).join(", ")} }`;
const lines = [
  "-- Generated by tools/map-data/bosses-locales.mjs from DBM-Raids-Vanilla and DBM-Dungeons' locale tables.",
  "-- English remains in Data/Forever/Places.lua; entries absent from DBM keep that fallback.",
  "",
  "local _, ns = ...",
  "local translated = {",
];
let translated = 0;
for (const locale of locales.filter((locale) => locale !== "enUS")) {
  lines.push(`\t${locale} = {`);
  for (const { id, names } of bosses) {
    const sources = sourcesFor(raidMaps.has(String(id)) ? "raid" : "dungeon");
    const localized = names.map((name) => {
      const normalized = normalize(name);
      const aliasesForName = aliases.get(normalized);
      const alternatives = Array.isArray(aliasesForName) ? aliasesForName : aliasesForName ? [aliasesForName] : [];
      const candidates = sources.map((source) => [normalized, ...alternatives].map((key) => source.get(key)).find(Boolean)).find(Boolean);
      const values = candidates?.[localeNames[locale]];
      return values?.size ? [...values][0] : fallbackTranslations[normalized]?.[localeNames[locale]] ?? name;
    });
    if (localized.some((name, i) => name !== names[i])) translated++;
    lines.push(`\t\t[${id}] = ${lua(localized)},`);
  }
  lines.push("\t},");
}
lines.push("}", "", "local bosses = translated[GetLocale and GetLocale() or \"enUS\"]", "if bosses then", "\tfor mapID, names in pairs(bosses) do ns.MapPlaces.bosses[mapID] = names end", "end");
writeFileSync(out, `${lines.join("\n")}\n`);
console.error(`wrote ${out}: ${bosses.length} maps, ${translated} localized map entries`);
