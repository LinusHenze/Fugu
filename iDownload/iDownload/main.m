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
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <mach/mach.h>

#include "common.h"
#include "server.h"
#include "install.h"

extern char **environ;

mach_port_t bPort = MACH_PORT_NULL;

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

int main(int argc, char **argv) {
#ifdef iOS
    if (getpid() == 1) {
        // We're the first process
        // Spawn launchd
        pid_t pid = fork();
        if (pid != 0) {
            // Parent
            char *args[] = { "/sbin/launchd", NULL };
            execve("/sbin/launchd", args, environ);
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
        // Re-Exec with the bp
        execv(argv[0], argv);
        return -1;
    } else if (getpid() == 2) {
        // After exec
        // Set PATH
        setenv("PATH", "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin", 1);
        
        // Check if launchctl and bash exist
        // If they do, load all daemons
        if (FILE_EXISTS("/.Fugu_installed") && FILE_EXISTS("/bin/bash") && FILE_EXISTS("/sbin/launchctl")) {
            pid_t pid = fork();
            if (pid == 0) {
                // Child
                char *args[] = { "/bin/bash", "-c", "/sbin/launchctl load /Library/LaunchDaemons/*", NULL };
                execve("/bin/bash", args, environ);
                exit(-1);
            }
            
            // Parent
            waitpid(pid, NULL, 0);
            
            // Inject substitute
            if (FILE_EXISTS("/etc/rc.d/substitute")) {
                pid_t pid = fork();
                if (pid == 0) {
                    // Child
                    char *args[] = { "/etc/rc.d/substitute", NULL };
                    execve("/etc/rc.d/substitute", args, environ);
                    exit(-1);
                }
                
                // Sleep a bit
                sleep(5);
                
                // Parent
                waitpid(pid, NULL, 0);
                
                // Kill cfprefsd in case it was running already
                pid = fork();
                if (pid == 0) {
                    // Child
                    char *args[] = { "/bin/bash", "-c", "/sbin/launchctl stop com.apple.cfprefsd.xpc.daemon", NULL };
                    execve("/bin/bash", args, environ);
                    exit(-1);
                }
                
                // Parent
                waitpid(pid, NULL, 0);
            }
        } else {
            // Install didn't succeed yet
            requestInstall();
        }
    }
#endif
    
    launchServer();
    
    CFRunLoopRun();
}
