#!/bin/bash
#
#  crosstool-works, to speed up things ..
#  2014 <gokhan@clxdev.net>
#
#
#  edited by deVbug
#
#  ref: https://github.com/uboreas/ctworks
#

set -e

CTCWD=`pwd`
dmg="disk.dmg"
mount_point="disk"
ctng_dir="crosstool-ng"

function dmgeject() {
	if [ "`mount | grep "${CTCWD}/${mount_point}"`" == "" ]; then
		echo " > DMG not mounted."
	else
		hdiutil detach -force "./${mount_point}"
	fi
}

function dmgcreate() {
	if [ -e "${dmg}" ]; then
		echo " ! DMG file (${dmg}) already exist."
		return
	fi
	dmgsize="10g"
	if [ "`mount | grep "${CTCWD}/${mount_point}"`" != "" ]; then
		echo " > Mount point (${mount_point}) not available (already mounted)."
		return
	fi
	hdiutil create ./${dmg} -ov -volname "crosstool-ng" -fs "Case-sensitive Journaled HFS+" -type UDIF -size "${dmgsize}"
	sync
}

function dmgattach() {
	if [ "`mount | grep "${CTCWD}/${mount_point}"`" != "" ]; then
		echo " > Disk ${dmg} already mounted."
		return
	fi
	if [ ! -f "${dmg}" ]; then
		dmgcreate
		sleep 1
		sync
	fi
	if [ "`mount | grep "${CTCWD}/${mount_point}"`" != "" ]; then
		echo " > Disk ${dmg} already mounted."
		return
	fi
	mkdir -p "${CTCWD}/${mount_point}"
	cd "${CTCWD}"
	hdiutil attach -mountpoint "./${mount_point}" "./${dmg}"
	echo
}

function ctngconfig() {
	dmgattach
	
	cd "${CTCWD}/${mount_point}"
	
	if [ ! -e "${ctng_dir}" ]; then
		git clone https://github.com/crosstool-ng/crosstool-ng "${ctng_dir}"
	fi

	cd "${ctng_dir}"
	
	if [ -e "ct-ng" ] && [ -z "$1" ]; then
		echo " > crosstool-ng already configured."
		return
	fi

	if [ -e ".git" ]; then
		git pull origin master || true
	fi

	if [ "$1" = "re" ]; then
		make clean || true
		./bootstrap
	fi
	if [ ! -e "configure" ]; then
		./bootstrap
	fi
	
	sed -i 's/gcc -static/gcc -Bstatic/g' configure || true
	sed -i 's/ -static / -Bstatic /g' scripts/crosstool-NG.sh.in || true
	for file in patches/gdb/*/100-*.patch
	do
		already_patch=`grep "config.in" ${file}` || true
		if [ -z "${already_patch}" ]; then
			cat "${CTCWD}/patches/gdb.patch" >> "${file}"
		fi
	done
	
	./configure --enable-local
	make
	
	echo 
	echo "Please run below commands to build toolchain"
	echo "
	cd ${PWD}
	./ct-ng menuconfig
	ulimit -n 2048
	./ct-ng build
	"
}

function ctngexec() {
	if [ -z "$1" ]; then
		echo " ! build restart required steps name."
		return
	fi
	
	cd "${CTCWD}/${mount_point}/${ctng_dir}"
	
	./ct-ng "$1"
}

function cthelp() {
   echo "
  1. Create case sensitive file system in a disk image:
	> ${0} create
     or you may use existing one;
	> ${0} attach
  2. Run with \"config\" switch to configure crosstool-ng and follow instructions displayed to build toolchain
	> ${0} configure
  3. Run with \"eject\" switch to unmount disk image.
	> ${0} eject
  Notes:
   - You may need to restart from a step when something goes wrong;
     ${0} list-steps
     ${0} restart libc_start_files
"
}

function build_with_config() {
	ctngconfig
	
	cd "${CTCWD}"
	
	if [ ! -z "${1}" ]; then
		cp -rf "${1}" "${CTCWD}/${mount_point}/${ctng_dir}/.config"
	fi
	if [ ! -e "${CTCWD}/${mount_point}/${ctng_dir}/.config" ]; then
		echo " ! linaro config not found."
		return
	fi
	
	cd "${CTCWD}/${mount_point}/${ctng_dir}"
	
	if [ -e "${CTCWD}/tarballs" ]; then
		mkdir -p "CTOSX/tarballs"
		cp -rf "${CTCWD}/tarballs"/* "CTOSX/tarballs/"
	fi

	unset LIBRARY_PATH
	unset C_INCLUDE_PATH
	unset CPLUS_INCLUDE_PATH
	export CT_TARGET_SKIP_CONFIG_SUB=y

	ulimit -n 2048
	./ct-ng build
}

function build_restart() {
	if [ -z "$1" ]; then
		echo " ! build restart required steps name."
		return
	fi
	
	cd "${CTCWD}/${mount_point}/${ctng_dir}"

	unset LIBRARY_PATH
	unset C_INCLUDE_PATH
	unset CPLUS_INCLUDE_PATH
	export CT_TARGET_SKIP_CONFIG_SUB=y

	RESTART=$1 ./ct-ng build
}


if [ -z "$1" ]; then
	
	dmgcreate
	dmgattach
	ctngconfig
	
elif [ "$1" = "eject" ]; then
	
	dmgeject
	
elif [ "$1" = "create" ]; then
	
	dmgcreate
	
elif [ "$1" = "attach" ]; then
	
	dmgattach
	
elif [ "$1" = "configure" ]; then
	
	ctngconfig
	
elif [ "$1" = "reconfigure" ]; then
	
	ctngconfig re
	
elif [ "$1" = "menuconfig" ]; then
	
	ctngexec "menuconfig"
	
elif [ "$1" = "list-steps" ]; then
	
	ctngexec "list-steps"
	
elif [ "$1" = "restart" ]; then
	
	build_restart "$2"
	
elif [ "$1" = "build" ]; then
	
	build_with_config "${2}"
	
elif [ "$1" = "help" ]; then
	
	cthelp
	
else
	
	cthelp
	
fi



