#!/bin/bash

mount -o remount,rw /mnt/root-ro
touch /mnt/root-ro/disable-root-ro

cp /mnt/root-ro/etc/fstab.rw /mnt/root-ro/etc/fstab

echo "now reboot"


