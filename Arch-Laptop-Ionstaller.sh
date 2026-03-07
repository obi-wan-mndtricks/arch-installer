#!/bin/bash
set -e

echo "Arch Laptop Installer"

lsblk -dpnoNAME,SIZE | grep -Ev "boot|rpmb|loop"

read -rp "Disk: " DISK
read -rp "Hostname: " HOST
read -rp "Username: " USER

sgdisk --zap-all "$DISK"

sgdisk -n1:0:+512M -t1:ef00 "$DISK"
sgdisk -n2:0:0 -t2:8300 "$DISK"

EFI="${DISK}1"
ROOT="${DISK}2"

[[ "$DISK" == *"nvme"* ]] && EFI="${DISK}p1" ROOT="${DISK}p2"

mkfs.fat -F32 "$EFI"
mkfs.btrfs -f "$ROOT"

mount "$ROOT" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

mount -o compress=zstd,subvol=@ "$ROOT" /mnt
mkdir -p /mnt/{boot,home}
mount "$EFI" /mnt/boot
mount -o compress=zstd,subvol=@home "$ROOT" /mnt/home

pacstrap /mnt \
base linux linux-firmware \
sudo nano \
networkmanager dbus \
mesa \
plasma-desktop sddm \
pipewire pipewire-pulse \
btrfs-progs \
tlp powertop thermald

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt <<EOF

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

echo LANG=en_US.UTF-8 > /etc/locale.conf
echo $HOST > /etc/hostname

passwd

useradd -m -G wheel $USER
passwd $USER

sed -i 's/# %wheel/%wheel/' /etc/sudoers

systemctl enable NetworkManager
systemctl enable sddm
systemctl enable tlp
systemctl enable thermald

bootctl install

EOF