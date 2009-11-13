#!/bin/sh
########################################################
# this script installs Go on a linux system.
# it currently only supports Debian like systems:
# Debian/Ubuntu/Xandros/ etc.
# But it should be relatively easy to add other systems.
########################################################
PWD=`pwd`
DEB_PKGMGMT=apt-get
DEB_PKGMGMT_INSTALL_FLAGS="-y install"
DEB_PKGLIST="
build-essential
bison
mercurial
"
GOURL="https://go.googlecode.com/hg/"
GOROOT=${HOME}/go
GOARCH="bad"
GOOS=linux
GOBIN=${GOROOT}/bin

echo "Go Programming Language install Script"
echo "++++++++++++++++++++++++++++++++++++++"

echo "Stage I: System Detection"
echo "++++++++++++++++++++++++++++++++++++++"

if [ -r /etc/debian_version ]; then
	echo "NOTE: Debian Detected (supported)"
	echo "NOTE: Assuming apt-get is set up!"
	PKGMGMT=${DEB_PKGMGMT}
	PKGMGMT_INSTALL_FLAGS=${DEB_PKGMGMT_INSTALL_FLAGS}
	PKGLIST=${DEB_PKGLIST}
else
	echo "Please add support your of your system here"
	echo "You need to add your own 3 variables:"
	echo "    PKGMGMT"
	echo "    PKGMGMT_INSTALL_FLAGS"
	echo "    PKGLIST"
########### for example Fedora should look like this:
#if [ -r /etc/redhat_release ]; then
#	echo "NOTE: RedHat Detected (supported)"
#	echo "NOTE: Assuming apt-get is set up!"
#	PKGMGMT=yum
#	PKGMGMT_INSTALL_FLAGS=-i
#	PKGLIST="bison ${DEB_PKGLIST}
#else
# here comes additional system.
#fi
	
fi

if [ `uname -s` != "Linux" ]; then
	echo "Wrong Kernel! Exitting!"
	exit 1
fi

case `uname -m` in
	i?86)
		msg "uname returned: `uname -m`"
		GOARCH=386
		;;
	x86_64)

		msg "uname returned: `uname -m`"
		GOARCH="amd64"
	;;
	*)
		echo "FATAL ERROR: Wrong Architecture! Exitting"
		exit 1
	;;
esac
	
echo "Stage II: Prerequisite Packages"
echo "++++++++++++++++++++++++++++++++++++++"
## install devtools and stuff:
msg "Installing packages: ${PKGLIST}"
sudo ${PKGMGMT} ${PKGMGMT_INSTALL_FLAGS} ${PKGLIST}


echo -n "Stage III: Shell Type: "
UN=`whoami`
USH=`getent passwd ${UN} | cut -d: -f7`
echo ${USH} | grep csh > /dev/null
if [ $? -ne 0 ]; then
	# we're on sh-like shell
	SH=1
	SHCONF=~/.bashrc
	SETENV="export "
	EQUAL="="
	echo "sh!"
else
	# we're on csh-like shell
	SHCONF=~/.cshrc
	SETENV="setenv "
	EQUAL=" "
	echo "csh!"
fi
echo "++++++++++++++++++++++++++++++++++++++"

echo "Stage IV: Setup shell environment"
echo "++++++++++++++++++++++++++++++++++++++"

if [ ! -r ${SHCONF} ]; then
	touch ${SHCONF}
fi

cat >> ${SHCONF} << EOF
### Go Environment:
${SETENV}GOROOT${EQUAL}${HOME}/go
${SETENV}GOARCH${EQUAL}${GOARCH}
${SETENV}GOOS${EQUAL}linux
${SETENV}GOBIN${EQUAL}${GOROOT}/bin
${SETENV}PATH${EQUAL}${GOBIN}:${PATH}
EOF

## actually set it for THIS script:
export GOROOT=${HOME}/go
export GOARCH=${GOARCH}
export GOOS=linux
export GOBIN=${GOROOT}/bin
export PATH=${GOBIN}:${PATH}

if [ -d ${GOROOT} ]; then
	echo "WARNING: the GOROOT folder (${GOROOT}) already exists."
	echo "Continuing will rename it to ${GOROOT}.old"
	echo -n "Do you want to continue?[Y/n]"
	read ans
	echo -n "Considering this as a \""
	if [ ! -z $ans ]; then
		case ${ans} in
			[Nn]*)	
				echo "No\""
				cd ${PWD}
				exit 2
			;;
			[yY]*)
				echo "Yes\""
				mv ${GOROOT} ${GOROOT}.old
			;;
			*)
				echo "No\""
				mv ${GOROOT} ${GOROOT}.old
			;;
		esac
	else
		echo "No\""
		cd ${PWD}
		exit 2
	fi
fi

echo "Stage V: Fetching Go Source Code"
echo "++++++++++++++++++++++++++++++++++++++"
hg clone -r release ${GOURL} ${GOROOT}

if [ 0 -ne $? ]; then
	echo "For Some reason Mercurial failed!"
	echo "Maybe a network problem... ?"
	cd ${PWD}
	rm -fr ${GOROOT}
	echo "I've removed the GOROOT folder."
	echo "Please:"
	echo "        1. clean up your ${SHCONF} from ^GO variables"
	echo "        2. run the script once again when network is back"
	exit 3
fi

mkdir -p ${GOBIN}

cd ${GOROOT}/src

echo "Stage VI (the last): Building Go"
echo "++++++++++++++++++++++++++++++++++++++"
./all.bash
if [ $? -eq 0 ]; then
	echo "Hooray! You have Go Installed!"
else
	echo "Oops. Something went wrong during the building."
	echo "Please check it and report on #go-nuts at irc.freenode.net"
fi

cd ${PWD}
