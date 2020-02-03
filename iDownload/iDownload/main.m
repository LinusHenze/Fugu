//
//  main.c
//  iDownload
//
//  Created by Linus Henze on 27.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include <Foundation/Foundation.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <limits.h>
#include <dirent.h>
#include <sys/stat.h>
#include <arpa/inet.h>
#include <mach/mach.h>

extern char **environ;

mach_port_t bPort = MACH_PORT_NULL;

#define VERSION "1.0"

mach_port_t task_for_pid_backdoor(int pid) {
    mach_port_t   psDefault;
    mach_port_t   psDefault_control;
    
    task_array_t  tasks;
    mach_msg_type_number_t numTasks;
    
    kern_return_t kr;
    
    kr = processor_set_default(mach_host_self(), &psDefault);
    
    kr = host_processor_set_priv(mach_host_self(), psDefault, &psDefault_control);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "host_processor_set_priv failed with error %x\n", kr);
        mach_error("host_processor_set_priv",kr);
        return 0;
    }
    
    kr = processor_set_tasks(psDefault_control, &tasks, &numTasks);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr,"processor_set_tasks failed with error %x\n",kr);
        return 0;
    }
    
    for (int i = 0; i < numTasks; i++) {
        int foundPid;
        pid_for_task(tasks[i], &foundPid);
        if (foundPid == pid) return tasks[i];
    }
    
    return MACH_PORT_NULL;
}

void insertBP() {
    task_set_bootstrap_port(mach_task_self(), bPort);
}

void removeBP() {
    task_set_bootstrap_port(mach_task_self(), MACH_PORT_NULL);
}

int runCommand(FILE *f, char *argv[]) {
    dup2(fileno(f), STDIN_FILENO);
    dup2(fileno(f), STDOUT_FILENO);
    dup2(fileno(f), STDERR_FILENO);
    
    pid_t pid = fork();
    if (pid == 0) {
        execve(argv[0], argv, environ);
        fprintf(stderr, "child: Failed to launch! Error: %s\r\n", strerror(errno));
        exit(-1);
    }
    
    // Now wait for child
    int status;
    waitpid(pid, &status, 0);
    
    return status;
}

bool readToNewline(FILE *f, char *buf, size_t size) {
    size_t cmdOffset = 0;
    memset(buf, 0, size);
    
    while (1) {
        // Read incoming data
        size_t status = fread(buf + cmdOffset, 1, 1, f);
        if (status < 1) {
            return false;
        }
        
        cmdOffset++;
        if (cmdOffset >= (size-1)) {
            fprintf(f, "\r\nERROR: Command to long!\r\n");
            cmdOffset = 0;
            memset(buf, 0, size);
            continue;
        }
        
        // Check if there is a newline somewhere
        char *loc = strstr(buf, "\n");
        if (!loc) {
            continue;
        }
        
        // There is
        if ((loc - 1) >= buf) {
            if (*(loc - 1) == '\r') {
                loc--;
            }
        }
        
        *loc = 0;
        return true;
    }
}

char *getParameter(char *buf, int param) {
    char *loc = buf;
    
    for (int i = 0; i < param; i++) {
        loc = strstr(loc, " ");
        if (!loc) {
            return NULL;
        }
        
        loc++; // Skip over the space
    }
    
    char *next = strstr(loc, " ");
    if (!next) {
        return strdup(loc);
    }
    
    *next = 0;
    char *data = strdup(loc);
    *next = ' ';
    
    return data;
}

/*
 * https://stackoverflow.com/questions/10323060/printing-file-permissions-like-ls-l-using-stat2-in-c
 */
void printInfo(FILE *f, char *file) {
    struct stat fileStat;
    if(lstat(file, &fileStat) < 0) {
        fprintf(f, "info: %s\r\n", strerror(errno));
        return;
    }
    
    fprintf(f, "---------------------------\r\n");
    fprintf(f, "Information for %s\r\n", file);
    fprintf(f, "---------------------------\r\n");
    if (fileStat.st_size != 1) {
        fprintf(f, "File Size: \t\t%lld bytes\r\n", fileStat.st_size);
    } else {
        fprintf(f, "File Size: \t\t1 byte\r\n");
    }
    
    //fprintf(f, "Number of Links: \t%d\r\n", fileStat.st_nlink);
    //fprintf(f, "File inode: \t\t%llu\r\n", fileStat.st_ino);
    
    fprintf(f, "File Permissions: \t");
    fprintf(f, (S_ISDIR(fileStat.st_mode)) ? "d" : "-");
    fprintf(f, (fileStat.st_mode & S_IRUSR) ? "r" : "-");
    fprintf(f, (fileStat.st_mode & S_IWUSR) ? "w" : "-");
    if (fileStat.st_mode & S_ISUID) {
        fprintf(f, (fileStat.st_mode & S_IXUSR) ? "s" : "S");
    } else {
        fprintf(f, (fileStat.st_mode & S_IXUSR) ? "x" : "-");
    }
    fprintf(f, (fileStat.st_mode & S_IRGRP) ? "r" : "-");
    fprintf(f, (fileStat.st_mode & S_IWGRP) ? "w" : "-");
    if (fileStat.st_mode & S_ISGID) {
        fprintf(f, (fileStat.st_mode & S_IXGRP) ? "s" : "S");
    } else {
        fprintf(f, (fileStat.st_mode & S_IXGRP) ? "x" : "-");
    }
    fprintf(f, (fileStat.st_mode & S_IROTH) ? "r" : "-");
    fprintf(f, (fileStat.st_mode & S_IWOTH) ? "w" : "-");
    fprintf(f, (fileStat.st_mode & S_IXOTH) ? "x" : "-");
    fprintf(f, "\r\n");
    fprintf(f, "File Owner UID: \t%d\r\n", fileStat.st_uid);
    fprintf(f, "File Owner GID: \t%d\r\n", fileStat.st_gid);
    
    if (S_ISLNK(fileStat.st_mode)) {
        fprintf(f, "\r\n");
        fprintf(f, "The file is a symbolic link.\r\n");
    }
}

void printHelp(FILE *f) {
    fprintf(f, "iDownload has a bash-like interface\r\n");
    fprintf(f, "The following commands are supported:\r\n");
    fprintf(f, "exit:                     Close connection\r\n");
    fprintf(f, "exit_full:                Close connection and terminate iDownload\r\n");
    fprintf(f, "pwd:                      Print current working directory\r\n");
    fprintf(f, "cd <directory>:           Change directory\r\n");
    fprintf(f, "ls <optional path>:       List directory\r\n");
    fprintf(f, "clear:                    Clear screen\r\n");
    fprintf(f, "write <name> <size>:      Create file with name and size\r\n");
    fprintf(f, "                          Send file data afterwards\r\n");
    fprintf(f, "cat <file>:               Print contents of file\r\n");
    fprintf(f, "rm <file>:                Delete file\r\n");
    fprintf(f, "rmdir <folder>:           Delete an empty folder\r\n");
    fprintf(f, "chmod <mode> <file>:      Chmod a file. Mode must be octal\r\n");
    fprintf(f, "chown <uid> <gid> <file>: Chown a file\r\n");
    fprintf(f, "info <file>:              Print file infos\r\n");
    fprintf(f, "mkdir <name>:             Create a directory\r\n");
    fprintf(f, "exec <program> <args>:    Launch a program\r\n");
    fprintf(f, "help:                     Print this help\r\n");
    fprintf(f, "\r\n");
}

void update_springboard_plist(){
    NSDictionary *springBoardPlist = [NSMutableDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.apple.springboard.plist"];
    [springBoardPlist setValue:@YES forKey:@"SBShowNonDefaultSystemApps"];
    [springBoardPlist writeToFile:@"/var/mobile/Library/Preferences/com.apple.springboard.plist" atomically:YES];
    
    NSDictionary* attr = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithShort:0755], NSFilePosixPermissions,@"mobile",NSFileOwnerAccountName,NULL];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:@"/var/mobile/Library/Preferences/com.apple.springboard.plist" error:&error];
}

void handleConnection(int socket) {
    FILE *f = fdopen(socket, "r+b");
    if (f == NULL) {
        return;
    }
    
    fprintf(f, "===================================================================\r\n");
    fprintf(f, "          iDownload Copyright (C) 2019/2020 Linus Henze            \r\n");
    fprintf(f, "                     Part of the Fugu Jailbreak                    \r\n");
    fprintf(f, "                 https://github.com/LinusHenze/Fugu                \r\n\r\n");
    fprintf(f, "   This is free software, and you are welcome to redistribute it   \r\n");
    fprintf(f, "under certain conditions; See the LICENSE file for more information\r\n\r\n");
    fprintf(f, "           If you paid for this software, you got scammed          \r\n");
    fprintf(f, "===================================================================\r\n\r\n");
    fprintf(f, "iDownload version " VERSION " ready.\r\n");
    
    char *cmdBuffer = malloc(2048);
    
    while (1) {
        fprintf(f, "iDownload> ");
        
        // Read a command
        if (!readToNewline(f, cmdBuffer, 2048)) {
            break;
        }
        
        // Guaranteed to always exist
        char *cmd = getParameter(cmdBuffer, 0);
        
        // Execute it
        if (strcmp(cmd, "help") == 0) {
            printHelp(f);
        } else if (strcmp(cmd, "exit") == 0) {
            fprintf(f, "Bye!\r\n");
            break;
        } else if (strcmp(cmd, "exit_full") == 0) {
            fprintf(f, "Completely exiting.\r\nBye!\r\n");
            exit(0);
        } else if (strcmp(cmd, "pwd") == 0) {
            char cwd[PATH_MAX];
            memset(cwd, 0, PATH_MAX);
            getcwd(cwd, PATH_MAX);
            
            fprintf(f, "%s\r\n", cwd);
        } else if (strcmp(cmd, "cd") == 0) {
            char *param = getParameter(cmdBuffer, 1);
            if (param) {
                if (chdir(param) < 0) {
                    fprintf(f, "cd: %s\r\n", strerror(errno));
                }
                
                free(param);
            } else {
                fprintf(f, "Usage: cd <directory>\r\n");
            }
        } else if (strcmp(cmd, "ls") == 0) {
            char *param = getParameter(cmdBuffer, 1);
            if (!param) {
                param = strdup(".");
            }
            
            DIR *d;
            struct dirent *dir;
            d = opendir(param);
            if (d) {
                readdir(d); // Skip .
                readdir(d); // Skip ..
                
                while ((dir = readdir(d)) != NULL) {
                    fprintf(f, "%s\r\n", dir->d_name);
                }
                
                closedir(d);
            } else {
                fprintf(f, "ls: %s\r\n", strerror(errno));
            }
            
            free(param);
        } else if (strcmp(cmd, "clear") == 0) {
            fprintf(f, "\E[H\E[J");
        } else if (strcmp(cmd, "write") == 0) {
            char *name = getParameter(cmdBuffer, 1);
            if (name) {
                char *length = getParameter(cmdBuffer, 2);
                if (length) {
                    FILE *file = fopen(name, "wb+");
                    if (file) {
                        size_t size = strtoul(length, NULL, 0);
                        if (size) {
                            char *buffer = malloc(size);
                            if (buffer) {
                                size_t offset = 0;
                                while (offset < size) {
                                    size_t read = fread(buffer + offset, 1, 1, f);
                                    if (read < 1) {
                                        // OOPS
                                        offset = 0;
                                        break;
                                    }
                                    
                                    offset++;
                                }
                                
                                if (offset == size) {
                                    fwrite(buffer, size, 1, file);
                                    fprintf(f, "\r\nFile written.\r\n");
                                } else {
                                    fprintf(f, "\r\nFailed to write file!\r\n");
                                }
                                
                                fclose(file);
                                
                                free(buffer);
                            } else {
                                fprintf(f, "write: %s\r\n", strerror(errno));
                            }
                        } else {
                            fprintf(f, "Usage: write <file> <length in bytes>\r\n");
                        }
                    } else {
                        fprintf(f, "write: %s\r\n", strerror(errno));
                    }
                    
                    free(length);
                } else {
                    fprintf(f, "Usage: write <file> <length in bytes>\r\n");
                }
                
                free(name);
            } else {
                fprintf(f, "Usage: write <file> <length in bytes>\r\n");
            }
        } else if (strcmp(cmd, "cat") == 0) {
            char *param = getParameter(cmdBuffer, 1);
            if (param) {
                FILE *file = fopen(param, "rb");
                if (file) {
                    fseek(file, 0, SEEK_END);
                    size_t size = ftell(file);
                    fseek(file, 0, SEEK_SET);
                    
                    char *buffer = malloc(size + 1);
                    memset(buffer, 0, size + 1);
                    if (buffer) {
                        fread(buffer, size, 1, file);
                        fprintf(f, "%s\r\n", buffer);
                    } else {
                        fprintf(f, "cat: %s\r\n", strerror(errno));
                    }
                    
                    fclose(file);
                } else {
                    fprintf(f, "cat: %s\r\n", strerror(errno));
                }
                
                free(param);
            } else {
                fprintf(f, "Usage: cat <file>\r\n");
            }
        } else if (strcmp(cmd, "rm") == 0) {
            char *param = getParameter(cmdBuffer, 1);
            if (param) {
                if (unlink(param) < 0) {
                    fprintf(f, "rm: %s\r\n", strerror(errno));
                }
                
                free(param);
            } else {
                fprintf(f, "Usage: rm <file>\r\n");
            }
        } else if (strcmp(cmd, "chmod") == 0) {
            char *modeStr = getParameter(cmdBuffer, 1);
            if (modeStr) {
                char *param = getParameter(cmdBuffer, 2);
                if (param) {
                    size_t mode = strtoul(modeStr, NULL, 8);
                    if (mode) {
                        if (chmod(param, mode) < 0) {
                            fprintf(f, "chmod: %s\r\n", strerror(errno));
                        }
                    } else {
                        fprintf(f, "Usage: chmod <mode, octal> <file>\r\n");
                    }
                    
                    free(param);
                } else {
                    fprintf(f, "Usage: chmod <mode, octal> <file>\r\n");
                }
                
                free(modeStr);
            } else {
                fprintf(f, "Usage: chmod <mode, octal> <file>\r\n");
            }
        } else if (strcmp(cmd, "chown") == 0) {
            char *uid_str = getParameter(cmdBuffer, 1);
            if (uid_str) {
                char *gid_str = getParameter(cmdBuffer, 2);
                if (gid_str) {
                    char *param = getParameter(cmdBuffer, 3);
                    if (param) {
                        size_t uid = strtoul(uid_str, NULL, 0);
                        size_t gid = strtoul(gid_str, NULL, 0);
                        if (chown(param, (uid_t) uid, (gid_t) gid) < 0) {
                            fprintf(f, "chown: %s\r\n", strerror(errno));
                        }
                        
                        free(param);
                    } else {
                        fprintf(f, "Usage: chown <uid> <gid> <file>\r\n");
                    }
                    
                    free(gid_str);
                } else {
                    fprintf(f, "Usage: chown <uid> <gid> <file>\r\n");
                }
                
                free(uid_str);
            } else {
                fprintf(f, "Usage: chown <uid> <gid> <file>\r\n");
            }
        } else if (strcmp(cmd, "rmdir") == 0) {
            char *param = getParameter(cmdBuffer, 1);
            if (param) {
                if (rmdir(param) < 0) {
                    fprintf(f, "rmdir: %s\r\n", strerror(errno));
                }
                
                free(param);
            } else {
                fprintf(f, "Usage: rmdir <folder, empty>\r\n");
            }
        } else if (strcmp(cmd, "info") == 0) {
            char *param = getParameter(cmdBuffer, 1);
            if (param) {
                printInfo(f, param);
                free(param);
            } else {
                fprintf(f, "Usage: info <file>\r\n");
            }
        } else if (strcmp(cmd, "mkdir") == 0) {
            char *param = getParameter(cmdBuffer, 1);
            if (param) {
                if (mkdir(param, 0777) < 0) {
                    fprintf(f, "mkdir: %s\r\n", strerror(errno));
                }
                
                free(param);
            } else {
                fprintf(f, "Usage: mkdir <name>\r\n");
            }
        } else if (strcmp(cmd, "exec") == 0) {
            char *param = getParameter(cmdBuffer, 1);
            if (param) {
                int ctr = 2;
                while (1) {
                    char *param = getParameter(cmdBuffer, ctr++);
                    if (!param) {
                        break;
                    }
                    
                    free(param);
                }
                
                char **buf = malloc(ctr * sizeof(char*));
                buf[0] = param;
                
                ctr = 2;
                while (1) {
                    char *param = getParameter(cmdBuffer, ctr);
                    if (!param) {
                        break;
                    }
                    
                    buf[(ctr++) - 1] = param;
                }
                
                buf[ctr - 1] = NULL;
                
                int status = runCommand(f, buf);
                while (*buf) {
                    free(*buf);
                    buf++;
                }
                
                fprintf(f, "exec: Child status: %d\r\n", status);
            } else {
                fprintf(f, "Usage: exec <program> <args>\r\n");
            }
        } else if (strcmp(cmd, "bootstrap") == 0) {
            // Bootstrap the device from /bootstrap.tar using /bin/tar
            int fd = open("/bootstrap.tar", O_RDONLY);
            if (fd != -1) {
                close(fd);
                
                fd = open("/bin/tar", O_RDONLY);
                if (fd != -1) {
                    close(fd);
                    
                    fprintf(f, "Extracting bootstrap.tar\r\n");
                    fflush(f);
                    
                    chdir("/");
                    
                    // All the stuff exists, let's go!
                    char *argv[] = { "/bin/tar", "--preserve-permissions", "--no-overwrite-dir", "-xvf", "/bootstrap.tar", NULL };
                    int res = runCommand(f, argv);
                    if (res == 0) {
                        fd = open("/usr/bin/ssh-keygen", O_RDONLY);
                        if (fd != -1) {
                            close(fd);
                            fprintf(f, "Generating SSH Host Keys...\r\n");
                            fflush(f);
                            char *args[] = { "/usr/bin/ssh-keygen", "-A", NULL };
                            runCommand(f, args);
                        }
                        
                        fd = open("/usr/bin/launchctl", O_RDONLY);
                        if (fd != -1) {
                            close(fd);
                            
                            fprintf(f, "Launching services...\r\n");
                            fflush(f);
                            char *launchctlArgs[] = { "/bin/bash", "-c", "/usr/bin/launchctl load /Library/LaunchDaemons/*", NULL };
                            res = runCommand(f, launchctlArgs);
                            if (res == 0) {
                                fprintf(f, "Successfully started services!\r\n");
                                fflush(f);
                            } else {
                                fprintf(f, "Failed to start services!\r\n");
                                fflush(f);
                            }
                        } else {
                            fprintf(f, "bootstrap: Couldn't find launchctl, cannot start services!\r\n");
                            fflush(f);
                        }
                        
                        fd = open("/usr/libexec/cydia/firmware.sh", O_RDONLY);
                        if (fd != -1) {
                            close(fd);
                            
                            fprintf(f, "Installing firmware package...\r\n");
                            fflush(f);
                            
                            char *args[] = { "/bin/bash", "-c", "/usr/libexec/cydia/firmware.sh", NULL };
                            runCommand(f, args);
                            
                            fd = open("/sileo.deb", O_RDONLY);
                            if (fd != -1) {
                                close(fd);
                                
                                fd = open("/cydia.deb", O_RDONLY);
                                if (fd != -1) {
                                    close(fd);
                                    
                                    fd = open("/swift.deb", O_RDONLY);
                                    if (fd != -1) {
                                        close(fd);
                                        
                                        fprintf(f, "Installing Sileo...\r\n");
                                        fflush(f);
                                        
                                        setenv("PATH", "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin", 1);
                                        char *args[] = { "/usr/bin/dpkg", "-i", "/sileo.deb", "/cydia.deb", "/swift.deb", NULL };
                                        runCommand(f, args);
                                        
                                        fprintf(f, "Adding chimera repo...\r\n");
                                        fflush(f);
                                        
                                        FILE *fp = fopen("/etc/apt/sources.list.d/chimera.list", "w+");
                                        if (fp) {
                                            fwrite("deb https://repo.chimera.sh/ ./", 31, 1, fp);
                                            fclose(fp);
                                        } else {
                                            fprintf(f, "bootstrap: Failed to add chimera repo!\r\n");
                                            fflush(f);
                                        }
                                        
                                        fprintf(f, "Updating Springboard Plist...\r\n");
                                        fflush(f);
                                        update_springboard_plist();
                                        
                                        fprintf(f, "Running uicache...\r\n");
                                        fflush(f);
                                        char *argsUicache[] = { "/bin/bash", "-c", "uicache --path /Applications/Sileo.app --respring", NULL };
                                        runCommand(f, argsUicache);
                                    }
                                }
                            }
                        }
                    } else {
                        fprintf(f, "bootstrap: tar failed!\r\n");
                    }
                    
                    // We're done
                    break;
                } else {
                    fprintf(f, "bootstrap: /bin/tar is missing!\r\n");
                }
            } else {
                fprintf(f, "bootstrap: /bootstrap.tar is missing!\r\n");
            }
        } else {
            fprintf(f, "Unknown command %s!\r\n", cmdBuffer);
        }
        
        free(cmd);
    }
    
    fclose(f);
}

int main(int argc, char **argv) {
#ifdef iOS
    pid_t pid = fork();
    if (pid != 0) {
        execve("/sbin/launchd", argv, environ);
        return -1;
    }
    
    // Sleep a bit for launchd to do some work
    sleep(3);
    
    // Now get task port for something that has a valid bootstrap port
    int ctr = getpid() + 1;
    mach_port_t port = 0;
    while (!port) {
        port = task_for_pid_backdoor(ctr++);
        if (!port) {
            continue;
        }
        
        mach_port_t bp = 0;
        task_get_bootstrap_port(port, &bp);
        if (!bp) {
            port = 0;
            continue;
        }
        
        bPort = bp;
        insertBP();
    }
    
    // Now we've got a valid bootstrap port!
    // Check if launchctl and bash exist
    // If they do, load all daemons
    int fd = open("/bin/bash", O_RDONLY);
    if (fd != -1) {
        close(fd);
        fd = open("/usr/bin/launchctl", O_RDONLY);
        if (fd != -1) {
            close(fd);
            
            pid_t pid = fork();
            if (pid == 0) {
                // Child
                char *args[] = { "/bin/bash", "-c", "/usr/bin/launchctl load /Library/LaunchDaemons/*", NULL };
                execve("/bin/bash", args, environ);
                exit(-1);
            }
            
            // Parent
            waitpid(pid, NULL, 0);
        }
    }
#endif
    
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        return -1;
    }
    
    dup2(server_fd, 10);
    close(server_fd);
    server_fd = 10;
    
    int option = 1;
    
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEPORT, &option, sizeof(option)) < 0) {
        return -1;
    }
    
    struct sockaddr_in server;
    
    memset(&server, 0, sizeof (server));
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = inet_addr("127.0.0.1");
    server.sin_port = htons(1337);
    
    if (bind(server_fd, (struct sockaddr*) &server, sizeof(server)) < 0) {
        return -1;
    }
    
    if (listen(server_fd, SOMAXCONN) < 0) {
        return -1;
    }
    
    while (1) {
        int new_socket = accept(server_fd, NULL, NULL);
        if (new_socket == -1) {
            if (errno == EINTR) {
                continue;
            }
            
            return -1;
        }
        
        dispatch_async(dispatch_queue_create(NULL, NULL), ^{
            handleConnection(new_socket);
        });
    }
}
