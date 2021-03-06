#!/bin/bash
source script.bash
format_image
mount_partitions
debootstrap  --variant=minbase --arch=i386 bionic mnt/root http://dk.archive.ubuntu.com/ubuntu/
#diff /etc/apt/sources.list local/etc/apt/sources.list
cp -a local/etc/apt/sources.list  mnt/root/etc/apt/
echo -e '#!/bin/sh\nexit 101' > mnt/root/usr/sbin/policy-rc.d
chmod a+x mnt/root/usr/sbin/policy-rc.d
export DEBIAN_FRONTEND=noninteractive
chroot mnt/root apt-get update
chroot mnt/root apt-get -y install apt-utils
chroot mnt/root apt-get clean

chroot mnt/root apt-get -y install initramfs-tools
chroot mnt/root apt-get -y install dhcpcd5
chroot mnt/root apt-get -y install dropbear-bin
chroot mnt/root apt-get -y install dropbear-run
chroot mnt/root apt-get -y install openssh-client
chroot mnt/root apt-get -y install smbclient
#chroot mnt/root apt-get -y install libsmbclient
chroot mnt/root apt-get -y install cifs-utils
chroot mnt/root apt-get -y install net-tools
chroot mnt/root apt-get -y install iputils-ping
chroot mnt/root apt-get -y install usbmount
chroot mnt/root apt-get -y install acpid
#chroot mnt/root apt-get -y install libc-bin
#chroot mnt/root apt-get -y install dialog
chroot mnt/root apt-get -y install vim-tiny
chroot mnt/root apt-get -y install bash-completion
chroot mnt/root apt-get -y install less
chroot mnt/root apt-get -y install usbutils
chroot mnt/root apt-get -y install man
chroot mnt/root apt-get -y install beep
#chroot mnt/root apt-get -y install mc
chroot mnt/root apt-get clean
chroot mnt/root apt-get -y install xserver-xorg-video-intel
chroot mnt/root apt-get -y install x11-xserver-utils

#chroot mnt/root apt-get -y install nodm

chroot mnt/root apt-get -y install xinit
chroot mnt/root apt-get -y install xterm
chroot mnt/root apt-get -y install libgtk-3-0
chroot mnt/root apt-get -y install locales
chroot mnt/root locale-gen en_US.UTF-8
chroot mnt/root apt-get clean
chroot mnt/root apt-get -y install cups

# To get lpq 

chroot mnt/root apt-get -y install cups-bsd

apply_local_changes

# From here

chroot mnt/root systemctl enable xserver.service
chroot mnt/root systemctl enable egtouch.service
chroot mnt/root systemctl enable kiosk-application.service

# To here is to be added to apply_local_changes

chroot mnt/root apt-get -y install linux-image-5.0.0-23-generic
create_boot_cfg $KERNEL_VERSION /dev/sda2 > mnt/root/boot/linux.cfg
cp -a local.bootloader/*  mnt/root

cp -a local.Abaxis/mnt/boot/background.tga mnt/boot/
cp -a local.Abaxis/mnt/boot/middle.tga mnt/boot/

mkdir -p mnt/boot/grub
echo -e "(hd0) $DEV_WHOLE\n" > mnt/boot/grub/device.map

chroot mnt/root apt-get -y install x11-apps
chroot mnt/root apt-get -y install libasound2

# To Check:
# If this package is installed before the kernel (linux-image-5.0.0-23-generic)
# initramfs script root-ro (which enables the rw overlay file system) is not run at boot.
# Don't know exactly why but it has to do with the package running update-initramfs -u
# after the install

chroot mnt/root apt-get -y install linux-modules-extra-5.0.0-23-generic
chroot mnt/root apt-get -y install dbus-x11

# Remove /var/log/journald to disable journald persistant logging

chroot mnt/root rm -rf /var/log/journal

grub-install --compress=gz --debug --grub-mkdevicemap=$PWD/mnt/boot/grub/device.map --boot-directory=$PWD/mnt/boot/ $DEV_WHOLE

unmount_partitions

echo "image generated"

