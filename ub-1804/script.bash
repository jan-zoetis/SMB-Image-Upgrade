#!/bin/bash
###############################################################################################################
# The Linux image creation script for SMB
# Author: Edgar Lakis <ela@tekpartner.dk>
# Version 1.0 16-08-2013
###############################################################################################################
# The script can be executed directly, but it can also be sourced, and functions invoked interactively from shell
# This way it is easier to follow process and observe the outcome.
# Some information about this steps and created image can be found in the delivered documentation.
# 
# DISCLAIMER: The missing tools or changes of the tool syntax might make the script fail.
###############################################################################################################

# Some settings for non-interactive execution (if we are not sourced)
[ -z "$PS1" ] && set -x -e # show executed commands & exit after a command fails


###############################################################################################################
## CONFIGURATION section: The safest place to make changes ;-) 

# Base name of the resulting image
#export IMG=card.img
export IMG=card.img.test
#export IMG=card.img.Abaxis.Bionic
export IMG_SIZE=$((4*10**9/(1024*1024))) # 4 bilion bytes, rounded to MiB
echo "working on image file: $IMG"
# Image partitioning in MiBytes
export START_BOOTFS=1  # start of first partition (space left for partition information, bootloader. Also enforces partition alignment for improved performance)
export SIZE_BOOTFS=10     # size of boot partition
#export SIZE_BOOTFS=7     # size of boot partition
export SIZE_ROOTFS=1784 # size of rootfs
#export SIZE_ROOTFS=1600 # size of rootfs
export SIZE_ROOTFS2=10 # The second root partitions used to allow simple upgrades. Set this to small number if this is not needed.
#export SIZE_ROOTFS2=$SIZE_ROOTFS # The second root partitions used to allow simple upgrades. Set this to small number if this is not needed.
export SIZE_USERFS=$((IMG_SIZE-START_BOOTFS-SIZE_BOOTFS-SIZE_ROOTFS-SIZE_ROOTFS2)) # The user partition will use remaining storage
# use raring (13.04) version of the cups
export CUPS_RARING=no	# We don't, the separate image with this future is created at the end

# List of customised images to build:
# This requires corresponding logo in 
# 
# modifications to filesystem:
# In directories "local.<name>"
# and kernel splash logo in "src/logo/<name>_kernel.ppm" 
export CUSTOMISATIONS="Abaxis QuickVet"

# Should we build everything from scratch (=yes). If (=no), the content of earlier build saved in <partition>fs.tgz is used to polulate partitions 
export RUN_FULL_BUILD=no

# Kernel version information
if [ "$RUN_FULL_BUILD" != "yes" ] ; then
    # Use previously compiled kernel 
    #export KERNEL_VERSION=3.8.13.25   # Version name in compiled result (the number might increase with kernel package updates)
    export KERNEL_VERSION=5.0.0-23-generic   # Version name in compiled result (the number might increase with kernel package updates)
    export KERNEL_DEB=src/linux-image-${KERNEL_VERSION}_*.deb # The debian package of compiled kernel
else
    # Build kernel from scratch
    # Ubuntu names kernel source packages and directories slightly different, hence 2 different names for the same thing
    export KERNEL_PACKAGE=linux-image-3.8.0-44-generic # Name of Ubuntu kernel package
    export KERNEL_SRCDIR=linux-lts-raring-3.8.0        # Directory name after package is extracted
    if [ -f src/$KERNEL_SRCDIR/include/config/kernel.release ] ; then
	export KERNEL_VERSION=`cat src/$KERNEL_SRCDIR/include/config/kernel.release `
    else
	export KERNEL_VERSION=KERNEL_NOT_BUILD_YET
    fi
fi


###############################################################################################################
## Derived variables

# Partition offsets
export START_ROOTFS1=$((START_BOOTFS+SIZE_BOOTFS))
export START_ROOTFS2=$((START_ROOTFS1+SIZE_ROOTFS))
export START_USERFS=$((START_ROOTFS2+SIZE_ROOTFS2))
#export END_USERFS=$((IMG_SIZE-1))    # user partition until the end
export END_USERFS=$IMG_SIZE    # user partition until the end


# Number of parallel processes to use during build
export BUILD_CPUS=$((`cat /proc/cpuinfo | grep processor | wc -l`+1))

#default locale for build script
export LC_ALL=C




###############################################################################################################
## Script steps split into functions for easier reuse and readability

function format_image {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # Create empty image file
  
    dd if=/dev/zero of=$IMG bs=1M count=$((IMG_SIZE+1))

    # Partition image file
    parted --script $IMG -- mklabel msdos	# create the partition table
    parted --script $IMG -- unit MiB mkpart primary ext4 $START_BOOTFS $START_ROOTFS1  # bootloader
    parted --script $IMG -- set 1 boot on	# needed for some bootloaders (Syslinux)
    parted --script $IMG -- unit MiB mkpart primary ext4 $START_ROOTFS1 $START_ROOTFS2  # first ROOTFS
    parted --script $IMG -- unit MiB mkpart primary ext4 $START_ROOTFS2 $START_USERFS  # second ROOTFS
    parted --script $IMG -- unit MiB mkpart primary ext4 $START_USERFS  $END_USERFS
    # Show result
    fdisk -l $IMG

    prepare_partition_devices

    # Format partitions
    mkfs.ext4 $DEV_BOOTFS
    mkfs.ext4 $DEV_ROOTFS1
    mkfs.ext4 $DEV_ROOTFS2
    mkfs.ext4 $DEV_USERFS
)
}

function prepare_partition_devices {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # Remove old partition list (will recreate it at the end of the function) 
    rm -f .partitions 
    ## Make a block device for whole file (used to install bootloader)
    DEV_WHOLE=`losetup -f --show $IMG`

    ## Grub has problems with kpartx, so we use offsets in losetup
    # kpartx -a $DEV_WHOLE
    # read DEV_BOOTFS DEV_ROOTFS1 DEV_ROOTFS2 DEV_USERFS < <(kpartx -l $DEV_WHOLE| cut -d' ' -f 1 | tr '\n' ' '; echo)
    # #DEV_BOOTFS=/dev/mapper/$DEV_BOOTFS
    # ## grub workaround
    # DEV_BOOTFS=`losetup -f --show $IMG -o $((START_BOOTFS*1024*1024))   --sizelimit $((SIZE_BOOTFS*1024*1024))`
    # DEV_ROOTFS1=/dev/mapper/$DEV_ROOTFS1
    # DEV_ROOTFS2=/dev/mapper/$DEV_ROOTFS2
    # DEV_USERFS=/dev/mapper/$DEV_USERFS
    ## allocate a loop device for each partition
    DEV_BOOTFS=`losetup -f --show $IMG -o $((START_BOOTFS*1024*1024))   --sizelimit $((SIZE_BOOTFS*1024*1024))`
    DEV_ROOTFS1=`losetup -f --show $IMG -o $((START_ROOTFS1*1024*1024)) --sizelimit $((SIZE_ROOTFS*1024*1024))`
    #DEV_ROOTFS2=`losetup -f --show $IMG -o $((START_ROOTFS2*1024*1024)) --sizelimit $((SIZE_ROOTFS*1024*1024))`
    DEV_ROOTFS2=`losetup -f --show $IMG -o $((START_ROOTFS2*1024*1024)) --sizelimit $((SIZE_ROOTFS2*1024*1024))`
    #DEV_USERFS=`losetup -f --show $IMG -o $((START_USERFS*1024*1024))`
    DEV_USERFS=`losetup -f --show $IMG -o $((START_USERFS*1024*1024)) --sizelimit $((SIZE_USERFS*1024*1024))`

    # Save the list of partition devices to be reused later
    cat << EOF > .partitions
export DEV_WHOLE=$DEV_WHOLE
export DEV_BOOTFS=$DEV_BOOTFS
export DEV_ROOTFS1=$DEV_ROOTFS1
export DEV_ROOTFS2=$DEV_ROOTFS2
export DEV_USERFS=$DEV_USERFS
EOF
)
    # export partition device list
    source .partitions
}

function mount_partitions {
    source .partitions
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # Mount partitions
    mkdir -p mnt/{boot,root,user}
    mount $DEV_BOOTFS  mnt/boot
    mount $DEV_ROOTFS1 mnt/root
    mount $DEV_USERFS  mnt/user
    # Mount boot/user partitions on rootfs
    mkdir -p mnt/root/mnt/boot mnt/root/home/smb mnt/root/dev
    mount -o bind mnt/boot mnt/root/mnt/boot
    mount -o bind mnt/user mnt/root/home/smb
#    mount -o bind /dev mnt/root/dev
#    mount -o bind /dev/pts mnt/root/dev/pts
)
}

function unmount_partitions {
( set -x +e  # Don't exit, if command fails, to try unmounting everything
    #mount | grep "$PWD" | cut -d ' ' -f 3 | sort -r 
    #for d in mnt/root/home/smb/ mnt/root/mnt/boot mnt/root/dev/pts mnt/root/dev mnt/* ; do
    for d in mnt/root/home/smb/ mnt/root/mnt/boot mnt/* ; do
        umount $d;
	sync; # Sometimes the parent is busy just after the child has bin unmounted
    done

    # losetup -d $DEV_WHOLE $DEV_BOOTFS $DEV_ROOTFS1 $DEV_ROOTFS2 $DEV_USERFS
    losetup -a | grep "$PWD/$IMG" | cut -d ':' -f 1 | xargs -L1 -r losetup -vd 
)
}


function install_packages {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # Populate root filesystem with minimal installation
    debootstrap  --variant=minbase --arch=i386 bionic mnt/root http://dk.archive.ubuntu.com/ubuntu/
    cp -a local/etc/apt/sources.list  mnt/root/etc/apt/
    # Note: If the distribution is changed (from "precise"), the source.list has to also be updated.
    # These two changes should be enougth to change from Ubuntu 12.04 to any other version. 

    # Disable starting of the services during install (for dhcpcd, dropbear, cups etc.)
    echo -e '#!/bin/sh\nexit 101' > mnt/root/usr/sbin/policy-rc.d
    chmod a+x mnt/root/usr/sbin/policy-rc.d

    export DEBIAN_FRONTEND=noninteractive # make apt-get ask less questions

    chroot mnt/root apt-get update
    chroot mnt/root apt-get -y install apt-utils
    chroot mnt/root apt-get -y install initramfs-tools dhcpcd5 dropbear openssh-client smbclient libsmbclient cifs-utils net-tools iputils-ping
    chroot mnt/root apt-get clean
    chroot mnt/root apt-get -y install usbmount acpid apt-utils libc-bin
    # Some non required packages, added for convenience:
    #chroot mnt/root apt-get -y install dialog vim-tiny bash-completion less rsyslog usbutils man beep mc
    chroot mnt/root apt-get -y install dialog vim-tiny bash-completion less usbutils man beep mc
    # Clean the apt-get temp directories once in a while:
    chroot mnt/root apt-get clean
    chroot mnt/root apt-get -y install xserver-xorg-video-intel x11-xserver-utils nodm xinit xterm xorg libgtk-3-0 xinput-calibrator
    chroot mnt/root apt-get -y install locales
    chroot mnt/root locale-gen en_US.UTF-8
    # Clean the apt-get temp directories once in a while:
    chroot mnt/root apt-get clean

    install_cups

    # Clean the apt-get temp directories at the end
    chroot mnt/root apt-get clean
)
}

function install_cups {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # As a separate function to make Raring upgrade for separate image

    # Should we install raring version of CUPS (Package pinning configured in etc/apt/source.list.d/ and  etc/apt/preferences.d of mnt/root/)
    if [ "$CUPS_RARING" = "yes" ] ; then
	cp -a local.raring_cups/* mnt/root
	chroot mnt/root apt-get update
    fi
    #chroot mnt/root apt-get -y install hplip-cups foomatic-filters cups
    chroot mnt/root apt-get -y install cups 
    chroot mnt/root apt-get -y install hplip 
    chroot mnt/root apt-get -y install foomatic-filters
)
}


function apply_local_changes {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # Cron scripts don't make much sense on read-only system
    # Disable them (Note: consider adapting syslog rotation if needed)
    # The service is also disabled by local/etc/init/cron.override file 
    for f in mnt/root/etc/cron.* ; do mv $f ${f}_disabled ; mkdir $f ; done

    # Fix permissions/ownership of local files (just in case)
    ## root:root for all
    chown -R 0:0 local* 
    ## smb:smb for home
    chown -R 1000:1000 local*/home/smb
    ## root:lp for cups
    chown -R 0:7 local/home/smb/rootfs/etc/cups
    ## root:root for append_fstab, to allow SUID
    chown 0:0 local/home/smb/bin/append_fstab
    chmod u+s local/home/smb/bin/append_fstab
    # Copy files preserving permissions
    cp -a local/*  mnt/root

    # Move Cups configs (printers) into home for printer addition
    cp -a mnt/root/etc/cups mnt/root/home/smb/rootfs/etc/
    rm -r mnt/root/etc/cups
    ln -s /home/smb/rootfs/etc/cups mnt/root/etc/cups
    
    # Needed for read-only rootfs script
    echo aufs >> /etc/initramfs-tools/modules

    # Add user and set passwords
    chroot mnt/root useradd -s /bin/bash smb
    echo -e "smb:smb\nroot:smb" | chroot  mnt/root chpasswd
    # Allow smb to use Serial ports (/dev/ttyS*)
    chroot mnt/root usermod -aG dialout smb
    # Allow smb to use CUPS
    chroot mnt/root usermod -aG lpadmin smb
    chroot mnt/root usermod -aG lp smb
    # Allow users to invoke shutdown
    chmod u+s mnt/root/sbin/shutdown	
    # Add superuser and smb bin directories to the path for all users
    echo 'export PATH=$PATH:/usr/sbin:/sbin:/home/smb/bin' >> mnt/root/etc/profile
    ## alternatively, to root only
    ## echo 'export PATH=$PATH:/usr/sbin:/sbin:/home/smb/bin' >> mnt/root/root/.profile
    # Export locale
    echo '. /etc/default/locale' >> mnt/root/etc/profile
    # Disable eth* device persistence 
    echo -n > mnt/root/etc/udev/rules.d/70-persistent-net.rules
    echo -n > mnt/root/lib/udev/rules.d/75-persistent-net-generator.rules
)
}

function cleanup_rootfs {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # Some final cleaning up

    # remove DNS settings of the build machine
    echo -n > mnt/root/etc/resolv.conf
    # clean downloaded package cache
    chroot mnt/root apt-get clean
    # clean log files
    find mnt/root/var/log/ -type f -delete
    # clean tmp files
    rm -rf mnt/root/tmp/*
)
}

function install_kernel {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # Use old kernel build script?
    if false ; then
	test -d local.kernel/lib/modules/$KERNEL_VERSION || ( echo "KERNEL_VERSION not defined, please build the kernel first" ; exit 1 ; ) 
	cp -a local.kernel/*  mnt/root
	# Update initrd to use new kernel and custom scripts
        chroot mnt/root update-initramfs -c -k $KERNEL_VERSION  -v
    else
	if [ "$RUN_FULL_BUILD" = "yes" ] ; then
	    KERNEL_DEB=src/linux-image-${KERNEL_VERSION}_*.deb
	    test -f $KERNEL_DEB || ( echo "KERNEL_DEB not found, please build the kernel first" ; exit 1 ; ) 
	else
	    test -f $KERNEL_DEB || ( echo "KERNEL_DEB not found, please specify the correct path in build script" ; exit 1 ; ) 
	fi
	KPKG=`basename $KERNEL_DEB`
	cp src/$KPKG mnt/root/tmp/
	chroot mnt/root dpkg -i --force overwrite,overwrite-dir /tmp/$KPKG
	rm mnt/root/tmp/$KPKG
	test -f mnt/root/boot/vmlinuz-$KERNEL_VERSION -a -d mnt/root/lib/modules/$KERNEL_VERSION || ( echo "KERNEL_VERSION not found in the rootfs, ase build the kernel first" ; exit 1 ; ) 
	create_boot_cfg $KERNEL_VERSION /dev/sda2 > mnt/root/boot/linux.cfg
    fi
)
}

function create_boot_cfg {
	# Create a boot entry corresponding to the current kernel version.
	VERSION="$1"
	ROOT="$2"
	cat << EOF 
# grub commands to boot this partition (loaded from /mnt/boot/grub/grub.cfg)
#linux	/boot/vmlinuz-$VERSION root=$ROOT ro video=LVDS-1:640x480e video=VGA-1:d vt.global_cursor_default=0 console=ttyS1,19200n8 quiet splash root-ro-driver=aufs
#linux	/boot/vmlinuz-$VERSION root=$ROOT ro console=tty1 disable-root-ro=true
linux	/boot/vmlinuz-$VERSION root=$ROOT ro vt.global_cursor_default=0 console=ttyS1,19200n8 quiet splash root-ro-driver=aufs
initrd	/boot/initrd.img-$VERSION
boot
EOF
}


function install_bootloader {
    source .partitions
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    # Install bootloader
    cp -a local.bootloader/*  mnt/root
    mkdir -p mnt/boot/grub
    echo -e "(hd0) $DEV_WHOLE\n(hd0,msdos1) $DEV_BOOTFS" > mnt/boot/grub/device.map
    ## Automatic grub install script
    grub-install --debug --grub-mkdevicemap=$PWD/mnt/boot/grub/device.map --boot-directory=$PWD/mnt/boot/ $DEV_WHOLE 2>grub_log
    ## Alternatively: Manual grub instal (allows to use custom load.cfg)
    # cat << EOF > mnt/boot/grub/load.cfg
    # set root=hd0,msdos1
    # set prefix=($root)/grub 
    # EOF
    #  grub-mkimage -c mnt/boot/grub/load.cfg -d /usr/lib/grub/i386-pc -O i386-pc --output=mnt/boot/grub/core.img --prefix=/grub biosdisk ext2 part_msdos
    #  grub-setup --directory=mnt/boot/grub --device-map=mnt/boot/grub/device.map /dev/loop0
)
}

function fetch_kernel_source {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
	cd src
	apt-get -y source ${KERNEL_PACKAGE}
	apt-get -y build-dep ${KERNEL_PACKAGE}
)
}

function build_kernel {
    # depends: fetch_kernel_source
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
	cd src/${KERNEL_SRCDIR}
	echo "Will fail if multiple config files are present in ../"
	cp ../kernel_config* .config
	# Might need to update config if version don't match exactly
	yes '' | make oldconfig
	# Only include modules listed in kernel_modules
	make LSMOD=../kernel_modules localmodconfig
	# Uncomment if kernel customisations are needed:
	#make xconfig 

	# Build the kernel package
	make-kpkg -j $BUILD_CPUS --arch i386 --initrd  kernel-image
	KERNEL_VERSION=`cat ./include/config/kernel.release`

	# Change the splash logo
	for c in $CUSTOMISATIONS ; do
            echo "now current directory is:"
            pwd
	    pnmnoraw ../logo/${c}_kernel.ppm > drivers/video/logo/logo_linux_clut224.ppm
	    make -j $BUILD_CPUS bzImage
	    cp arch/x86/boot/bzImage ../../local.${c}/boot/vmlinuz-$KERNEL_VERSION
	done 
    )
    # This was set in the subshell, need to do it again
    export KERNEL_VERSION=`cat src/$KERNEL_SRCDIR/include/config/kernel.release`
}

function make_fs_snapshot {
	# Create tar archives of current image content
	VERSION=$1
	tar zcf bootfs_${VERSION}.tgz -C mnt/boot . 
	tar zcf userfs_${VERSION}.tgz -C mnt/user . 
	tar zcf rootfs_${VERSION}.tgz -C mnt/root . --exclude './home/smb' --exclude './mnt/boot' 
}

function restore_fs_snapshot {
	# Extract saved content of the partitions
	VERSION=$1
	for f in boot root user ; do
	    tar zxf ${f}fs_${VERSION}.tgz -C mnt/${f} . 
	done
}


function build_base_image {
# run in subshell, in case the file is sourced and function is used interactively
( set -x -e
    format_image
    # alternatively:
    #prepare_partition_devices # (if repartitioning is not needed)
    mount_partitions 

    if [ "$RUN_FULL_BUILD" = "yes" ] ; then
	# Build/Install everything from scratch
	install_packages 
	apply_local_changes 

	#fetch_kernel_source
	build_kernel
	
	# Create tar archives of final partition content for faster future install
	make_fs_snapshot "base"
    else
	# Use saved content of the partitions
	restore_fs_snapshot "base"
    fi

    install_kernel 
    install_bootloader 
    cleanup_rootfs

    unmount_partitions
    cp $IMG $IMG.base
)
}



###############################################################################################################
## Main command invocation

# Run commands if not sourced
if [ -z "$PS1" ]; then
    build_base_image

    # Apply image specific customisations
    for c in $CUSTOMISATIONS ; do
	cp $IMG.base $IMG
	prepare_partition_devices
	mount_partitions 
	cp -a local.$c/*  mnt/root
	unmount_partitions
	mv $IMG $IMG.$c
    done 

    # Create image with raring version of CUPS
    cp $IMG.base $IMG
    prepare_partition_devices
    mount_partitions 
    CUPS_RARING=yes
    install_cups
    cleanup_rootfs
    unmount_partitions
    mv $IMG $IMG.CUPS_raring

fi



