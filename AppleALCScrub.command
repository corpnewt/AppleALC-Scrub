#!/usr/bin/python
# 0.0.0
from Scripts import *
import os, tempfile, datetime, shutil, time, plistlib, sys

class ALCScrub:
    def __init__(self, **kwargs):
        self.r  = run.Run()
        self.dl = downloader.Downloader()
        self.re = reveal.Reveal()
        self.u  = utils.Utils("AppleALC Scrub")
        self.script_folder = "Scripts"
        self.hda_resources = "/System/Library/Extensions/AppleHDA.kext/Contents/Resources/"
        if not os.path.exists(self.hda_resources):
            print("AppleHDA.kext doesn't exist or isn't valid!")
            exit(1)
        self.layouts = self.get_hda_resources()
        
    def get_hda_resources(self):
        layouts = [self.layout_from_name(x) for x in os.listdir(self.hda_resources) if x.lower().startswith("layout")]
        return layouts

    def layout_from_name(self, name):
        return int(name.lower().replace("layout", "").replace(".xml.zlib", ""))

    def is_valid(self, file_path):
        layout = self.layout_from_name(os.path.basename(file_path))
        if layout in self.hda_resources:
            return True
        return False

    def get_valid(self, layouts):
        # Takes a list of layouts, and a list of valid layouts,
        # and returns a dict of { "old#" : new# } layouts
        # Only worries about changed
        val = self.get_hda_resources()
        val.sort()
        layouts.sort()
        outs = {}
        # Remove all valid layouts before walking
        for layout in layouts:
            if layout in val:
                val.remove(layout)
        for layout in layouts:
            if not len(val):
                # Out of valids
                break
            outs[str(layout)] = val.pop(0)
        return outs

    def get_local(self):
        self.u.head()
        print(" ")
        print("M. Main Menu")
        print("Q. Quit")
        print(" ")
        menu = self.u.grab("Please drag and drop an AppleALC source folder here and press [enter]:  ")
        if not len(menu):
            self.get_local()
            return
        if menu.lower() == "m":
            return
        elif menu.lower() == "q":
            self.u.custom_quit()
        
        # Check if it exist
        p = self.u.check_path(menu)
        if not p or not os.path.exists(os.path.join(p, "Resources")):
            self.u.grab("That path is not valid!", timeout=5)
            self.get_local()
            return
        
        # Got a path - let's walk it
        self.walk_path(os.path.join(p, "Resources"))

    def walk_path(self, path):
        # Path should point to resources - and ALC folders with Layout#.xml and Platform#.xml files
        # as well as Info.plist files
        changes = ""
        for folder in os.listdir(path):
            fp = os.path.join(path, folder)
            if not os.path.isdir(fp):
                continue
            # Found a folder - look for an Info.plist
            if not os.path.exists(os.path.join(fp, "Info.plist")):
                # No dice, keep walking
                continue
            # Let's load the Info.plist and patch stuff!
            try:
                info = plistlib.readPlist(os.path.join(fp, "Info.plist"))
            except:
                # Broken, keep walking
                continue
            # Let's iterate the Layouts and Platforms
            used = []
            layouts = info.get("Files", {}).get("Layouts", [])
            platforms = info.get("Files", {}).get("Platforms", [])
            
            old_layouts = [x["Id"] for x in layouts if x.get("Id", None) != None]
            new_layouts = self.get_valid(old_layouts)

            if not len(new_layouts):
                # Nothing to change
                continue
            # Let's replace!
            for layout in layouts:
                if not str(layout["Id"]) in new_layouts:
                    continue
                # We have a replacement
                layout["Id"] = new_layouts[str(layout["Id"])]
            for plat in platforms:
                if not str(plat["Id"]) in new_layouts:
                    continue
                plat["Id"] = new_layouts[str(plat["Id"])]
            plistlib.writePlist(info, os.path.join(fp, "Info.plist"))
            changes += folder + "\n" + "\n".join(["  {} --> {}".format(x, new_layouts[str(x)]) for x in sorted([int(y) for y in new_layouts])]) + "\n\n"
        return changes

    def download(self):
        temp = tempfile.mkdtemp()
        self.u.head("Building AppleALC")
        print(" ")
        cwd = os.getcwd()
        os.chdir(temp)
        changes = None
        try:
            print("Downloading Lilu...")
            self.r.run({"args":["git", "clone", "https://github.com/vit9696/Lilu"]})
            print("Building Lilu debug...")
            os.chdir("Lilu")
            self.r.run({"args":["xcodebuild", "-configuration", "Debug"]})
            print("Downloading AppleALC...")
            self.r.run({"args":["git", "clone", "https://github.com/vit9696/AppleALC"]})
            print("Copying Lilu.kext to AppleALC...")
            os.chdir("AppleALC")
            self.r.run({"args":["cp", "-R", "../build/Debug/Lilu.kext", "."]})
            print("Scrubbing AppleALC...")
            changes = self.walk_path(os.path.join(temp, "Lilu", "AppleALC", "Resources"))
            print("Building AppleALC...")
            self.r.run({"args":["xcodebuild"]})
            print("Zipping kext...")
            os.chdir("./build/Release")
            info_plist = plistlib.readPlist("AppleALC.kext/Contents/Info.plist")
            version = info_plist["CFBundleVersion"]
            file_name = "AppleALC-"+version+"-{:%Y-%m-%d %H.%M.%S}.zip".format(datetime.datetime.now())
            with open("Changes.txt", "w") as f:
                f.write(changes)
            self.r.run({"args":["zip", "-r", file_name, "AppleALC.kext", "Changes.txt", "-x", "*.dSYM*"]})
            dir_path = os.path.dirname(os.path.realpath(__file__))
            zip_path = os.getcwd() + "/" + file_name
            os.chdir(dir_path)
            kexts_path = os.getcwd() + "/Scrubbed"
            if not os.path.exists(kexts_path):
                os.mkdir(kexts_path)
            shutil.copy(zip_path, kexts_path)
        except Exception as e:
            print(str(e))
            self.u.grab("Press [enter] to return...")
        os.chdir(cwd)
        shutil.rmtree(temp)
        # Show it!
        if os.path.exists(os.path.join(kexts_path, file_name)):
            self.re.reveal(os.path.join(kexts_path, file_name))
        return changes

    def main(self):
        self.u.head()
        print(" ")
        print("1. Download AppleALC and Scrub")
        print("2. Get Local AppleALC Source to Scrub")
        print(" ")
        print("Q. Quit")
        print(" ")
        menu = self.u.grab("Please select an option:  ")
        if menu.lower() == "q":
            self.u.custom_quit()
        elif menu.lower() == "1":
            self.download()
        elif menu.lower() == "2":
            self.get_local()
        
        self.main()
        print(self.get_hda_resources())

if __name__ == '__main__':
    a = ALCScrub()
    # Check for args
    #if len(sys.argv) > 1:
    #    pass
    #    # We got command line args!
    #    # CloverExtractor.command /path/to/clover.pkg disk#s# /path/to/other/clover.pkg disk#s#
    #    c.quiet_copy(sys.argv[1:])
    #else:
    a.main()
