# Fugu
Fugu is the first open source jailbreak tool based on the checkm8 exploit.  
    
__UPDATE:__ Fugu will now install Sileo, SSH and Substitute automatically! Additionally, all changes to the root file system are now persistent. Put your iDevice into DFU mode, run `Fugu iStrap`, unlock your iDevice and follow the on-screen prompts.  
__IMPORTANT:__ This jailbreak is currently in development and only meant to be used by developers.  

# WARNING
**!!! ONLY DOWNLOAD FUGU FROM [https://github.com/LinusHenze/Fugu](https://github.com/LinusHenze/Fugu) AS IT IS VERY EASY TO CREATE A VERSION OF FUGU THAT CONTAINS MALWARE !!!**

# Supported Devices
Currently, the iPad Pro (2017, every size) and iPhone 7 are the only officially supported devices (on iOS 13 - 13.5.1).  
All devices with the A10/A10X CPU should be supported.  

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

# Installing Sileo, SSH and Substitute
**Fugu will now install Sileo, SSH and Substitute automatically!** Unlock your iDevice and follow the on-screen prompts. Make sure your iDevice is connected to the internet!

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
