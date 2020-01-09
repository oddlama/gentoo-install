**TL;DR:** Edit `scripts/config.sh` and execute `./install` in any live system.
EFI is required. This will partition the selected disk (with confirmation), and properly
install the selected stage3 gentoo system. The new system will be bootable with
`vanilla-kernel-bin` as the kernel. The script can optionally install sshd and
ansible to allow for easier management of the new system. Afterwards, you can continue
to roll-out your own advanced setup (LUKS, RAID, custom kernel).

# Gentoo installation script

This script performs a reasonably minimal installation of gentoo for an EFI system.
It does everything from the ground up, including creating partitions, downloading
and extracting the stage3 archive, initial system configuration and optionally installing
some additional software. The script only supports OpenRC and not systemd.

The system will temporarily use `sys-kernel/vanilla-kernel-bin`, which should be suitable
to boot most systems out of the box. I strongly recommend you to replace this kernel
with a custom built one, when the system is functional. If you are looking for a way
to properly manage your kernel configuration parameters, have a look at [kernconf](https://github.com/oddlama/kernconf).
There you will also find information on how to select the correct options for your system,
and information on kernel hardening.

## Overview

Here is a quick overview of what this script does:

* Does everything minus something
* Partition the device (efi, optional swap, linux root)
* Download and cryptographically verify the newest stage3 tarball
* Extract the stage3 tarball
* Sync portage tree
* Configure the base system
  - Set hostname
  - Set timezone
  - Set keymap
  - Generate and select locale
  - Prepare `zz-autounmask` files for portage autounmasking
* Select best 4 gentoo portage mirrors
* Install git (so you can add your portage overlays later)
* Install `sys-kernel/vanilla-kernel-bin` (temporarily, until you replace it)
* Copy kernel to efi partition
* Create boot entry using efibootmgr
* Generate fstab
* Lets you set a root password

Also, optionally the following will be done:

* Install sshd with secure config
* Install dhcpcd
* Install ansible, create ansible user and add authorized ssh key
* Install additional packages provided in config

Anything else is probably out of scope for this script,
but you can obviously do anything later on when the system is booted.
I highly recommend building a custom kernel and maybe encrypting your
root filesystem. Have a look at the [Recommendations](#Recommendations) section.

# Install

Installing gentoo with this script is simple.

1. Boot into the live system of your choice. As the script requires some utilities,
   I recommend using a live system where you can quickly install new software.
   Any [Arch Linux](https://www.archlinux.org/download/) live iso works fine.
2. Clone this repository
3. Edit `scripts/config.sh`, and particularily pay attention to
   the device which will be partitioned. The script will ask before partitioning,
   but better be safe than sorry.
4. Execute `./install`. The script will tell you if your live
   system is missing any required software.

## Config

The config file `scripts/config.sh` allows you to adjust some parameters of the installation.
The most important ones will probably be the device to partition, and the stage3 tarball name
to install. By default you will get the hardened nomultilib profile without systemd.

### Using existing partitions
 
If you want to use existing partitions, you will have to set `ENABLE_PARTITIONING=false`.
As the script uses uuids to refer to partitions, you will have to set the corresponding
partition uuid variables in the config (all variables beginning with `PARTITION_UUID_`).

## (Optional) sshd

The script can provide a fully configured ssh daemon with reasonably good security settings.
It will by default run on port `2222`, only allow ed25519 keys, restrict the key exchange
algorithms, disable any password based authentication, and only allow specifically mentioned
users to use ssh service (none by default).

To add a user to the list of allowed users, append `AllowUsers myuser` to `/etc/ssh/sshd_config`.
I recommend to create a separate group for all ssh users (like `sshusers`) and
to use `AllowGroups sshusers`. You should adjust this to your preferences when
the system is installed.

## (Optional) Ansible

This script can install ansible, create a system user for ansible and add an ssh key of
you choice to the `.authorized_keys` file. This allows you to directly use ansible when
the new system is up to configure the rest of the system.

## (Optional) Additional packages

You can enter any amount of additional packages to be installed on the target system.
These will simply be passed to a final `emerge` call before the script is done.
Autounmasking will be done automatically.

## Troubleshooting

The script checks every command for success, so if anything fails during installation,
you will be given a proper message of what went wrong. Inside the chroot,
most commands will be executed in some kind of try loop, and allow you to
fix problems interactively with a shell, to retry, or to skip the command.

# Recommendations

There are some things that you probably want to do after installing the base system,
or should consider:

* Read the news with `eselect news read`.
* Use a custom kernel (config and hardening, see [kernconf](https://github.com/oddlama/kernconf)), and remove `vanilla-kernel-bin`
* Adjust `/etc/portage/make.conf`
  - Set `CFLAGS` to `-O2 -pipe -march=native` for native builds
  - Set `CPU_FLAGS_X86` using the `cpuid2cpuflags` tool
  - Set `MAKEOPTS` to `-jN` with N being the amount of threads used for building
  - Set `EMERGE_DEFAULT_OPTS` to `-jN` if you want parallel emerging
  - Set `FEATURES="buildpkg"` if you want to build binary packages
* Use a safe umask like `umask 0077`
* Edit `/etc/ssh/sshd_config`, change the port if you want and create a `sshusers` group.
* Encrypt your system using LUKS
  - Remount the root fs read-only
  - Use `rsync -axHAWXS --numeric-ids --info=progress2 / /path/to/backup` to safely backup the whole
    system including all extended attributes.
  - Encrypt partition with LUKS
  - Use rsync to restore the saved system root.

# References

* [Sakaki's EFI Install Guide](https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide)
* [Gentoo AMD64 Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
