#!/usr/bin/env  python

import sys
import psutil
import commands

def distro_id_in(l):
    cmd = 'lsb_release -i'
    res = commands.getoutput(cmd)
    d = res.split('\t')[1]
    if d in l:
        return True
    return False

def get_procs_by_cmd_and_user(c,u):
   result = []
   for p in psutil.process_iter():
      try:
          if p.username != u:
             continue
          if p.cmdline.__class__ != list:
             if p.cmdline != c:
                continue
          elif p.cmdline[0] != c:
             continue
          result.append(p)
      except psutil.error.NoSuchProcess, e:
        ### maybe a warning!
        continue


   return result

def is_debian():
    supported_distros=list(['Debian','Ubuntu','Xandros'])
    return distro_id_in(supported_distros)

def is_redhat():
    supported_distros=list(['RedHat','CentOS','Scientific Linux'])
    return distro_id_in(supported_distros)

def get_apaches_on_debian():
   return get_procs_by_cmd_and_user('/usr/sbin/apache2', 'www-data')

def get_apaches_on_rhel():
   return get_procs_by_cmd_and_user('/usr/sbin/httpd', 'apache')

if is_debian():
    get_apaches = get_apaches_on_debian
elif is_redhat():
    get_apaches = get_apaches_on_rhel
else:
    print 'Unsupported OS!'
    sys.exit(1)

my_apaches = get_apaches()
for i in my_apaches:
    print i.pid
