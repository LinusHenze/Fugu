//
//  main.swift
//  Fugu
//
//  Created by Linus Henze on 30.09.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation
import Dispatch

print("===================================================================")
print("              Fugu Copyright (C) 2019/2020 Linus Henze             ")
print("                 https://github.com/LinusHenze/Fugu                \n")
print("   This is free software, and you are welcome to redistribute it   ")
print("under certain conditions; See the LICENSE file for more information\n")
print("           If you paid for this software, you got scammed          ")
print("===================================================================\n")

initSignalCatchers()

DispatchQueue.global().async {
    parseCommandLine(modules: [
        PwnModule.self,
        RmSigChksModule.self,
        iStrapModule.self,
        lzssModule.self,
    ])
}

dispatchMain()
