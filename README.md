# Fugu
Fugu is the first open source jailbreak tool based on the checkm8 exploit.  
  
__UPDATE:__ NewTerm and other Apps that do not rely on tweak injection should work now.  
__IMPORTANT:__ This jailbreak is currently in development and only meant to be used by developers. While it is possible to install Sileo (or Cydia), tweaks (and probably other stuff) won't work. Additionally, although the root filesystem is mounted read/write, __rebooting into non-jailbroken mode will reset the root filesystem back to stock!__

# Supported Devices
Currently, the iPad Pro (2017) and iPhone 7 are the only officially supported devices (on iOS 13 - 13.3.1).  

# Building
_Note that you can also download a precompiled version from the releases tab._  
To build Fugu, make sure you have Xcode and Homebrew installed.  
Using Homebrew, install `llvm` and `binutils`:
```bash
brew install llvm binutils
```
Afterwards, open the Fugu Xcode Project, select Fugu as target (if it's not already selected) and build it.  
This should generate Fugu and a shellcode folder in the build folder. You're now ready to go!

# Usage
I recommend you to just launch Fugu without any parameters to see all the options.  
If you would just like to jailbreak your iDevice, run the following:
```bash
Fugu iStrap
```
_You may need to run this command multiple times. If it won't work after the 4th try, enter DFU mode again._  

This will send iStrap (the kernel bootstrapper) to your iDevice together with iDownload (small application that can be used to upload files to the iDevice or execute commands). See _Components_ for more information.

# Installing Sileo (and SSH)
__IMPORTANT:__ While Sileo will work (including updating Sileo), most things you can install do not work or even break dpkg!  

Make sure you have `libusbmuxd` installed.  
You can install it through Homebrew:
```bash
brew install libusbmuxd
```
After installing usbmuxd, boot your iDevice into jailbroken mode (e.g. `Fugu iStrap`) and unlock it afterwards.  
Make sure it's still connected to your Mac via USB.  
You can now install Sileo using:
```bash
python install_sileo.py
```
This will download all the necessary files to install Sileo and install it.  
After the installation is done, you should see the Sileo Icon on your Homescreen.  
Aditionally, SSH will be running now. __Make sure to change the root/mobile passwords!__

# Components
Fugu consists of the following components:
* Fugu: The macOS Application that exploits your iDevice using checkm8 and uploads iStrap, iStrap loader and iDownload.
* iStrap loader: Small shellcode that patches iBoot and loads iStrap after iBoot is done.
* iStrap: The kernel bootstrapper. This is what you see on your iDevice during boot. Patches the kernel, injects boot arguments (if needed) and injects shellcode into the kernel.
* iDownload: Small application running on your iDevice. Will be installed during boot and launched instead of launchd. Forks itself and runs launchd. The forked copy will listen on Port 1337 (only on 127.0.0.1, use iproxy to connect) and provide a simple bash-like interface.

# Credits
* [@axi0mX](https://twitter.com/axi0mx) for the [checkm8 exploit](https://github.com/axi0mX/ipwndfu). This jailbreak wouldn't have been possible without it.
* miniz developers for the miniz library

# License
All code in this repository, except for third party code (see 3rdParty.txt), is released under the GPL v3.  

Fugu - iOS Jailbreaking tool  
Copyright (C) 2019/2020 Linus Henze  

This program is free software: you can redistribute it and/or modify  
it under the terms of the GNU General Public License as published by  
the Free Software Foundation, either version 3 of the License, or  
(at your option) any later version.  

This program is distributed in the hope that it will be useful,  
but WITHOUT ANY WARRANTY; without even the implied warranty of  
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the  
GNU General Public License for more details.  

You should have received a copy of the GNU General Public License  
along with this program.  If not, see <https://www.gnu.org/licenses/>.  

The full license text can be found in the LICENSE file.
