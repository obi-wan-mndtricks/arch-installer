#!/bin/bash

set -e

echo "=============================="
echo "     Arch Linux Installer"
echo "  (archinstall replacement)"
echo "=============================="

echo
echo "Available disks:"
lsblk -dpnoNAME,SIZE | grep -Ev "boot|rpmb|loop"

echo
read -rp "Disk to install to: " DISK
read -rp "Hostname: " HOSTNAME
read -rp "Username: " USERNAME

echo
echo "Enable LUKS encryption? (y/n)"
read ENCRYPT

echo
echo "WARNING: ALL DATA ON $DISK WILL BE ERASED"
read -rp "Type YES to continue: " CONFIRM
[ "$CONFIRM" != "YES" ] && exit

echo
echo "Partitioning disk..."

sgdisk --zap-all "$DISK"

sgdisk -n1:0:+512M -t1:ef00 "$DISK"
sgdisk -n2:0:0 -t2:8300 "$DISK"

EFI="${DISK}1"
ROOT="${DISK}2"

if [[ "$DISK" == *"nvme"* ]]; then
EFI="${DISK}p1"
ROOT="${DISK}p2"
fi

mkfs.fat -F32 "$EFI"

if [[ "$ENCRYPT" == "y" ]]; then

echo
echo "Setting up LUKS encryption"

cryptsetup luksFormat "$ROOT"
cryptsetup open "$ROOT" cryptroot
ROOT=/dev/mapper/cryptroot

fi

echo
echo "Creating Btrfs filesystem"

mkfs.btrfs -f "$ROOT"

mount "$ROOT" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots

umount /mnt

mount -o noatime,compress=zstd,subvol=@ "$ROOT" /mnt

mkdir -p /mnt/{boot,home,.snapshots}

mount -o noatime,compress=zstd,subvol=@home "$ROOT" /mnt/home
mount -o noatime,compress=zstd,subvol=@snapshots "$ROOT" /mnt/.snapshots

mount "$EFI" /mnt/boot

echo
echo "Installing base system..."

pacstrap /mnt \
base \
linux \
linux-firmware \
sudo \
vim \
networkmanager \
pipewire \
pipewire-pulse \
pipewire-alsa \
pipewire-jack \
plasma \
kde-applications \
sddm \
dolphin \
konsole \
git \
btrfs-progs \
intel-ucode \
amd-ucode

genfstab -U /mnt >> /mnt/etc/fstab

echo
echo "Configuring system..."

arch-chroot /mnt /bin/bash <<EOF

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname

cat <<HOSTS > /etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS

echo
echo "Set root password"
passwd

useradd -m -G wheel -s /bin/bash $USERNAME

echo
echo "Set password for $USERNAME"
passwd $USERNAME

sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager
systemctl enable sddm

echo
echo "Setting up zram swap"

pacman -S --noconfirm zram-generator

cat <<ZRAM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAM

bootctl install

ROOTUUID=\$(blkid -s UUID -o value $ROOT)

cat <<BOOT > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=UUID=\$ROOTUUID rw rootflags=subvol=@
BOOT

cat <<LOADER > /boot/loader/loader.conf
default arch
timeout 3
editor 0
LOADER

EOF

echo
echo "================================="
echo " Installation Complete!"
echo "================================="
echo
echo "You may reboot now."
