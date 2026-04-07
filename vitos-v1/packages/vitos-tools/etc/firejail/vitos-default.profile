# /etc/firejail/vitos-default.profile
include disable-common.inc
include disable-devel.inc
include disable-passwdmgr.inc

caps.drop all
nonewprivs
noroot
seccomp
shell none

private-tmp
private-dev
private-cache

read-only /etc
read-only /usr
whitelist ${HOME}/lab
mkdir ${HOME}/lab

netfilter
net none
