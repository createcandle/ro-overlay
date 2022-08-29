#!/bin/sh


#  Read-only Root-FS for Raspian using overlayfs
#  Version 1.1:
#  Changed to use /proc/mounts rathern than /etc/fstab for deriving the root filesystem.
#
#  Version 1:
#  Created 2017 by Pascal Suter @ DALCO AG, Switzerland to work on Raspian as custom init script
#  (raspbian does not use an initramfs on boot)
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see
#    <http://www.gnu.org/licenses/>.
#
#
#  Tested with Raspbian mini, 2017-01-11
#
#  This script will mount the root filesystem read-only and overlay it with a temporary tempfs 
#  which is read-write mounted. This is done using the overlayFS which is part of the linux kernel 
#  since version 3.18. 
#  when this script is in use, all changes made to anywhere in the root filesystem mount will be lost 
#  upon reboot of the system. The SD card will only be accessed as read-only drive, which significantly
#  helps to prolong its life and prevent filesystem coruption in environments where the system is usually
#  not shut down properly 
#
#  Install: 
#  copy this script to /sbin/overlayRoot.sh and add "init=/sbin/overlayRoot.sh" to the cmdline.txt 
#  file in the raspbian image's boot partition. 
#  I strongly recommend to disable swapping before using this. it will work with swap but that just does 
#  not make sens as the swap file will be stored in the tempfs which again resides in the ram.
#  run these commands on the booted raspberry pi BEFORE you set the init=/sbin/overlayRoot.sh boot option:
#  sudo dphys-swapfile swapoff
#  sudo dphys-swapfile uninstall
#  sudo update-rc.d dphys-swapfile remove
#
#  To install software, run upgrades and do other changes to the raspberry setup, simply remove the init= 
#  entry from the cmdline.txt file and reboot, make the changes, add the init= entry and reboot once more. 


#blk=$(lsblk)
#echo "blk before:" > /dev/kmsg
#echo "$blk" >> /dev/kmsg
#echo " " > /dev/kmsg

echo "in ro-root.sh" >> /dev/kmsg

early=
if grep -qs "(mmcblk0p1): Volume was not properly unmounted." dmesg;
then
  echo "candle: ro-root: DOING FSCK OF /BOOT"
  #early+=$'\nDOING FSCK OF /BOOT'
  early="DOING FSCK OF /BOOT"
  fsck.vfat /dev/mmcblk0p1 -a -v -V
fi

if grep -qs "(mmcblk0p2): Volume was not properly unmounted." dmesg;
then
  echo "candle: ro-root: DOING FSCK OF mmcblk0p2"
  early+=$'\nDOING FSCK OF mmcblk0p2'
  early="${early} DOING FSCK OF mmcblk0p2"
  fsck.ext4 -y /dev/mmcblk0p2
fi

if grep -qs "(mmcblk0p3): Volume was not properly unmounted." dmesg;
then
  echo "candle: ro-root: DOING FSCK OF mmcblk0p3"
  early="${early} DOING FSCK OF mmcblk0p3"
  fsck.ext4 -y /dev/mmcblk0p3
fi

if grep -qs "(mmcblk0p4): Volume was not properly unmounted." dmesg;
then
  echo "candle: ro-root: DOING FSCK OF mmcblk0p4"
  early="${early} DOING FSCK OF mmcblk0p4"
  fsck.ext4 -y /dev/mmcblk0p4
fi


if [ -d "/boot" ]; then
  mount -t vfat /dev/mmcblk0p1 /boot
  #ls /dev > /boot/ls_dev.txt

  # write results from early disk checks to log
  if [ -n "$early" ]; then
    echo "$early" >> /boot/candle_log.txt
  fi
  #blkk=$(lsblk)
  #echo "blk after:" > /dev/kmsg
  #echo "$blkk" >> /dev/kmsg
  #echo " " > /dev/kmsg

  #logfileboot=$(ls /boot)
  #echo "$logfileboot" >> /dev/kmsg

  # Abort if specific file exists
  if [ -e "/boot/candle_rw_once.txt" ] \
  || [ -e "/boot/candle_rw_keep.txt" ]  \
  || [ -e "/boot/bootup_actions.sh" ] \
  || [ -e "/boot/emergency.txt" ] \
  || [ -e "/boot/post_bootup_actions.sh" ] \
  || [ -e "/boot/restore_boot_backup.txt" ]  \
  || [ -e "/boot/restore_controller_backup.txt" ]; 
  then
    echo "candle: ro-root: detected file that prevents entering read-only mode"
    echo "candle: ro-root: detected file that prevents entering read-only mode" >> /dev/kmsg
    
    if [ -e "/bin/ply-image" ]; then
      if [ -e "/boot/rotate180.txt" ]; then
        /bin/ply-image /boot/splash_updating180.png
      else
        /bin/ply-image /boot/splash_updating.png
      fi
    fi
    
    umount /boot
    exec /sbin/init
    
  else
  
    if [ -e "/bin/ply-image" ]; then
      if [ -e "/boot/rotate180.txt" ]; then
        /bin/ply-image /boot/splash180alt.png
      else
        /bin/ply-image /boot/splashalt.png
      fi
    fi
    
  fi
  #umount /boot
else
  echo "Candle: ro-root: error: /boot mountpoint did not exist?"
  echo "Candle: ro-root: error: /boot did not exist?" >> /dev/kmsg
fi

#echo " " > /dev/kmsg



echo "Candle: ro-root: not skipping read-only disk mode"
echo "Candle: ro-root: not skipping read-only disk mode" >> /dev/kmsg


#if [ ! -s /etc/machine-id ]
#then
#    systemd-machine-id-setup --commit
#fi


fail(){
    echo -e "$1"
    echo "Candle: error in RO script: $1" >> /dev/kmsg
    if [ -f /boot/cmdline.txt ] || [ -f /boot/config.txt ]; then
        echo "ERROR in ro-root.sh: $1" >> /boot/candle_log.txt
    fi
    if [ -f /sbin/init ]; then
        umount /boot
        exec /sbin/init
    else
        /bin/bash
    fi
}

# load module
modprobe overlay
if [ $? -ne 0 ]; then
    fail "ERROR: missing overlay kernel module"
fi
# mount /proc
mount -t proc proc /proc

if [ -f /boot/developer.txt ]; then
  ls /dev > /boot/ls_dev.txt
  cat /proc/mounts > /boot/roc_mounts.txt
  ls /proc > /boot/ls_proc.txt
fi

# create a writable fs to then create our mountpoints 
mount -t tmpfs inittemp /mnt
if [ $? -ne 0 ]; then
    fail "ERROR: could not create a temporary filesystem to mount the base filesystems for overlayfs"
fi
mkdir /mnt/lower
mkdir /mnt/rw
mount -t tmpfs root-rw /mnt/rw
if [ $? -ne 0 ]; then
    fail "ERROR: could not create tempfs for upper filesystem"
fi
mkdir /mnt/rw/upper
mkdir /mnt/rw/work
mkdir /mnt/newroot

# mount root filesystem readonly 
rootDev=`awk '$2 == "/" {print $1}' /proc/mounts`
rootMountOpt=`awk '$2 == "/" {print $4}' /proc/mounts`
rootFsType=`awk '$2 == "/" {print $3}' /proc/mounts`
mount -t ${rootFsType} -o ${rootMountOpt},ro ${rootDev} /mnt/lower
if [ $? -ne 0 ]; then
    fail "ERROR: could not ro-mount original root partition"
fi
mount -t overlay -o lowerdir=/mnt/lower,upperdir=/mnt/rw/upper,workdir=/mnt/rw/work overlayfs-root /mnt/newroot
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount overlayFS"
fi



# create mountpoints inside the new root filesystem-overlay
mkdir /mnt/newroot/ro
mkdir /mnt/newroot/rw
# remove root mount from fstab (this is already a non-permanent modification)
grep -v "$rootDev" /mnt/lower/etc/fstab > /mnt/newroot/etc/fstab
echo "#the original root mount has been removed by overlayRoot.sh" >> /mnt/newroot/etc/fstab
echo "#this is only a temporary modification, the original fstab" >> /mnt/newroot/etc/fstab
echo "#stored on the disk can be found in /ro/etc/fstab" >> /mnt/newroot/etc/fstab

# fall back to third partition if fourth partition cannot be found
if ! lsblk | grep -q 'mmcblk0p4'; then
    sed -i ' 1 s|mmcblk0p4|mmcblk0p3|g' /mnt/newroot/etc/fstab
    if [ -f "/boot/cmdline.txt" ]; then
        echo "ERROR in ro-root.sh: fstab pointed to partition 4 but it did not exist?" >> /boot/candle_log.txt
    fi
fi

# Candle addition: unmount /boot
if [ -f "/boot/cmdline.txt" ]; then
  umount /boot
fi

# change to the new overlay root
cd /mnt/newroot
pivot_root . mnt
exec chroot . sh -c "$(cat <<END
# move ro and rw mounts to the new root
mount --move /mnt/mnt/lower/ /ro
if [ $? -ne 0 ]; then
    echo "ERROR: could not move ro-root into newroot"
    /bin/bash
fi
mount --move /mnt/mnt/rw /rw
if [ $? -ne 0 ]; then
    echo "ERROR: could not move tempfs rw mount into newroot"
    /bin/bash
fi
# unmount unneeded mounts so we can unmout the old readonly root
umount /mnt/mnt
umount /mnt/proc
umount -l -f /mnt/dev
umount -l -f /mnt
# continue with regular init
exec /sbin/init
END
)"
