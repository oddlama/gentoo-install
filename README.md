# Gentoo installation script

**TL;DR:** Installs gentoo on a new system, suited for both servers and desktops.
Optionally prepares ansible for automatic system configuration.
See [Install](#Install) for usage instructions.

---

This script will install a minimal (no-bloat) EFI bootable gentoo system.
It will stick closely to the [Gentoo AMD64 Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
and [Sakaki's EFI Install Guide](https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide).

What you will get:

* EFIstub kernel
* Minimal system configuration

What you can get optionally:

* LUKS
* EFI secure boot
* Initramfs (compiled into the kernel for EFIstub)

What you will **NOT** get: (i.e. you will have to do it yourself)

* X11 desktop environment
* A user (except root)
* Any form of RAID
* A specialized kernel (TODO insert links)


Only necessary configuration is applied to provide a common baseline system.
If you need advanced features such as an initramfs or a different
partitioning scheme, you can definitely use this script but will
have to make some adjustments to it.

The main purpose of this script is to provide a universal setup
which should be suitable for most use-cases (desktop and server installations).

#### Overview of executed tasks

* Check live system
* Sync time
* Partition disks
* Format partitions
* Download stage3
* Extract stage3
* Chroot into new system
* Update portage tree
* ... TODO MISSING!

#### GPT

The script will create GPT partition tables. If your system cannot use GPT,
this script is not suited for it.

#### EFI

It is assumed that your system can (and will) be booted via EFI.
This is not a strict requirement, but othewise you will be responsible
to make the system bootable.

This probably involves the following steps:

* Change partition type of `efi` partition to `ef02` (BIOS boot partition)
* Change partition name and filesystem name to `boot`
* Install and configure syslinux

Maybe there will be a convenience script for this at some point.
No promises though.

# Optional: Ansible ready

Optionally, this script can make the new system ready to be
used with ansible.

It will do the following steps for you:

* Create an ansible user
* Generate an ssh keypair (type configurable)
* Setup a secure sshd (safe ciphers, login only with keypair)
* Install ansible

# References

* [Sakaki's EFI Install Guide](https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide)
* [Gentoo AMD64 Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
