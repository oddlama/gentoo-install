#!/bin/bash

virt-install \
	--connect=qemu:///system \
	--name=vm-gentoo \
	--vcpus=2 \
	--memory=2048 \
	--cdrom=/vm/images/archlinux-2021.05.01-x86_64.iso \
	--disk path=/vm/disks/disk-vm-gentoo.disk,size=25 \
	--boot uefi \
	--os-variant=gentoo \
	--noautoconsole
#	--transient \
#	--graphics none \
	# --console pty,target.type=virtio \
	# --serial pty \
	# --extra-args 'console=ttyS0,115200n8 --- console=ttyS0,115200n8' \

# virsh
