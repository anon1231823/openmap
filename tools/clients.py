# The game clients OpenMap is built for, and where each one's data and textures go: the tools build
# for the client OPENMAP_CLIENT names (forever if unset), reading its build's tables and textures and
# writing OpenMap/Data/<folder> and OpenMap/Media/Textures/<folder>; its toc loads them
# (Data/<folder>/Client.lua names the folder in game). Each has its own release notes (changelog).
#
# in a tool:  sys.path.insert(0, os.path.join(<repo>, "tools")); import clients
import os

CLIENTS = {
    # folder: under Data/ and Media/Textures/; toc: in OpenMap/; build: the tables' and textures' on
    # wago.tools; product: the install's CASC product (tools/casc, OPENMAP_WOW); changelog: its release notes
    # (the in-game What's new, Data/<folder>/Changelog.lua, and its file's notes on CurseForge)
    "forever": {"folder": "Forever", "toc": "OpenMap.toc", "build": "1.60.1.70245", "product": "wowf",
                "changelog": "CHANGELOG.md"},
    "retail": {"folder": "Retail", "toc": "OpenMap_Mainline.toc", "build": "12.1.5.70448", "product": "wow",
               "changelog": "CHANGELOG-retail.md"},
}

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ADDON = os.path.join(REPO, "OpenMap")

NAME = os.environ.get("OPENMAP_CLIENT", "forever").lower()
if NAME not in CLIENTS:
    raise SystemExit("OPENMAP_CLIENT=%s: not one of %s" % (NAME, ", ".join(sorted(CLIENTS))))


def data(name=None):
    """the client's data folder (OpenMap/Data/<folder>)"""
    return os.path.join(ADDON, "Data", CLIENTS[name or NAME]["folder"])


def tex(name=None):
    """the client's texture folder (OpenMap/Media/Textures/<folder>)"""
    return os.path.join(ADDON, "Media", "Textures", CLIENTS[name or NAME]["folder"])


def toc(name=None):
    return os.path.join(ADDON, CLIENTS[name or NAME]["toc"])


FOLDER = CLIENTS[NAME]["folder"]
BUILD = CLIENTS[NAME]["build"]
PRODUCT = CLIENTS[NAME]["product"]
DATA = data()
TEX = tex()
