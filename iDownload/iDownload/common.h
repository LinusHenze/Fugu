//
//  common.h
//  iDownload
//
//  Created by Linus Henze on 09.02.20.
//  Copyright © 2020 Linus Henze. All rights reserved.
//

#ifndef common_h
#define common_h

#define VERSION       "1.1"
#define PLIST_VERSION 1

#define FILE_EXISTS(file) (access(file, F_OK ) != -1)

#endif /* common_h */
