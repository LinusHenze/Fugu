#!/usr/bin/env python3
from telnetlib import Telnet
import urllib.request
import hashlib
import os
import subprocess
import time
import tarfile
import gzip

print("===================================================================")
print("      install_sileo Script Copyright (C) 2019/2020 Linus Henze     ")
print("                     Part of the Fugu Jailbreak                    ")
print("                 https://github.com/LinusHenze/Fugu                \n")
print("   This is free software, and you are welcome to redistribute it   ")
print("under certain conditions; See the LICENSE file for more information\n")
print("           If you paid for this software, you got scammed          ")
print("===================================================================\n")

def upload(r, name, data):
    socket = r.get_socket()
    socket.sendall(b"write %s %d\n"%(name.encode(), len(data)))
    socket.sendall(data)
    r.read_until(b"iDownload>")
        
def extract_from_tar(tar, file):
    with tarfile.open(tar, mode="r:gz") as t:
        return t.extractfile(file).read()

def download(file):
    with urllib.request.urlopen("https://github.com/LinusHenze/iOS-bootstrap/raw/master/" + file) as url:
        with open(file, "wb+") as f:
            f.write(url.read())

if not os.path.exists("tar"):
    print("Downloading tar executable...")
    download("tar")
    
if not os.path.exists("bootstrap.tar.gz"):
    print("Downloading bootstrap.tar.gz...")
    download("bootstrap.tar.gz")

if not os.path.exists("org.coolstar.sileo_1.1.5_iphoneos-arm.deb"):
    print("Downloading Sileo...")
    download("org.coolstar.sileo_1.1.5_iphoneos-arm.deb")
    
if not os.path.exists("org.swift.libswift_5.0-electra2_iphoneos-arm.deb"):
    print("Downloading Swift...")
    download("org.swift.libswift_5.0-electra2_iphoneos-arm.deb")
    
if not os.path.exists("cydia_2.3_iphoneos-arm.deb"):
    print("Downloading Cydia Compatibility Package...")
    download("cydia_2.3_iphoneos-arm.deb")

print("Launching iproxy")

# Run iproxy
iproxy = subprocess.Popen(["/usr/local/bin/iproxy", "1337", "1337"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

try:
    time.sleep(1)

    print("Connecting to iDevice...")
    r = Telnet("localhost", 1337)
    r.read_until(b"iDownload>")

    print("Connected")
    
    print("Uploading tar executable...")
    
    with open("tar", "rb") as f:
        data = f.read()
    
    upload(r, "/bin/tar", data)
    
    r.write(b"chmod 755 /bin/tar\r\n")
    
    r.read_until(b"iDownload>")
    
    print("Uploading bootstrap.tar.gz...")
    
    with open("bootstrap.tar.gz", "rb") as f:
        data = f.read()
    
    upload(r, "/bootstrap.tar", gzip.decompress(data))
    
    print("Uploading Sileo...")
    
    with open("org.coolstar.sileo_1.1.5_iphoneos-arm.deb", "rb") as f:
        data = f.read()
    
    upload(r, "/sileo.deb", data)
    
    print("Uploading Swift...")
    
    with open("org.swift.libswift_5.0-electra2_iphoneos-arm.deb", "rb") as f:
        data = f.read()
    
    upload(r, "/swift.deb", data)
    
    print("Uploading Cydia Compatibility Package...")
    
    with open("cydia_2.3_iphoneos-arm.deb", "rb") as f:
        data = f.read()
    
    upload(r, "/cydia.deb", data)
    
    print("Done uploading!")
    
    print("Bootstrapping...")
    print("This will take a few seconds")
    r.write(b"bootstrap\n")
    
    r.read_until(b"Running uicache...")
    
    print("Done! iDevice will respring now")
finally:
    # Terminate iproxy
    iproxy.terminate()
