#!/bin/bash

# New version of cleaner_script
# Made by @fernandomaroto and @manuel 
# Any failed command will just be skiped, error message may pop up but won't crash the install process
# Net-install creates the file /tmp/run_once in live environment (need to be transfered to installed system) so it can be used to detect install option

userdel -r liveuser

if [ -f /tmp/new_username.txt ]
then
    NEW_USER=$(cat /tmp/new_username.txt)
else
    #NEW_USER=$(compgen -u |tail -n -1)
    NEW_USER=$(cat /tmp/$chroot_path/etc/passwd | grep "/home" |cut -d: -f1 |head -1)
fi

_check_internet_connection(){
    #ping -c 1 8.8.8.8 >& /dev/null   # ping Google's address
    curl --silent --connect-timeout 8 https://8.8.8.8 > /dev/null
}

_is_pkg_installed() {
    # returns 0 if given package name is installed, otherwise 1
    local pkgname="$1"
    pacman -Q "$pkgname" >& /dev/null
}

_remove_a_pkg() {
    local pkgname="$1"
    pacman -Rsn --noconfirm "$pkgname"
}

_remove_pkgs_if_installed() {
    # removes given package(s) and possible dependencies if the package(s) are currently installed
    local pkgname
    for pkgname in "$@" ; do
        _is_pkg_installed "$pkgname" && _remove_a_pkg "$pkgname"
    done
}

_vbox(){

    # Detects if running in vbox
    # packages must be in this order otherwise guest-utils pulls dkms, which takes longer to be installed
    local _vbox_guest_packages=(virtualbox-guest-dkms virtualbox-guest-utils)   
    local xx

    lspci | grep -i "virtualbox" >/dev/null
    if [[ $? == 0 ]]
    then
        # If using net-install detect VBox and install the packages
        if [ -f /tmp/run_once ]                  
        then
            for xx in ${_vbox_guest_packages[*]}
            do pacman -S $xx --noconfirm
            done
        fi   
        : 
    else
        for xx in ${_vbox_guest_packages[*]} ; do
            test -n "$(pacman -Q $xx 2>/dev/null)" && pacman -Rnsdd $xx --noconfirm
        done
        rm -f /usr/lib/modules-load.d/virtualbox-guest-dkms.conf
    fi
}

_vmware() {
    local vmware_guest_packages=(
        open-vm-tools
        xf86-input-vmmouse
        xf86-video-vmware
    )
    local xx

    case "$(device-info --vga)" in
        VMware*)
            pacman -S --needed --noconfirm "${vmware_guest_packages[@]}"
            ;;
        *) 
            for xx in "${vmware_guest_packages[@]}" ; do
                test -n "$(pacman -Q "$xx" 2>/dev/null)" && pacman -Rnsdd "$xx" --noconfirm
            done
            ;;
    esac
}

_common_systemd(){
    local _systemd_enable=(NetworkManager vboxservice org.cups.cupsd avahi-daemon systemd-networkd-wait-online systemd-timesyncd tlp gdm lightdm sddm)   
    local _systemd_disable=(multi-user.target pacman-init)           

    local xx
    for xx in ${_systemd_enable[*]}; do systemctl enable -f $xx; done

    local yy
    for yy in ${_systemd_disable[*]}; do systemctl disable -f $yy; done
}

_sed_stuff(){

    # Journal for offline. Turn volatile (for iso) into a real system.
    sed -i 's/volatile/auto/g' /etc/systemd/journald.conf 2>>/tmp/.errlog
    sed -i 's/.*pam_wheel\.so/#&/' /etc/pam.d/su
}

_clean_archiso(){

    local _files_to_remove=(                               
        /etc/sudoers.d/g_wheel
        /var/lib/NetworkManager/NetworkManager.state
        /etc/systemd/system/{choose-mirror.service,pacman-init.service,etc-pacman.d-gnupg.mount,getty@tty1.service.d}
        /etc/systemd/scripts/choose-mirror
        /etc/systemd/system/getty@tty1.service.d/autologin.conf
        /root/{.automated_script.sh,.zlogin}
        /etc/mkinitcpio-archiso.conf
        /etc/initcpio
        /etc/udev/rules.d/81-dhcpcd.rules
        /usr/bin/{calamares_switcher,cleaner_script.sh}
        /home/$NEW_USER/.config/qt5ct
        /home/$NEW_USER/{.xinitrc,.xsession,.xprofile}
        /root/{.xinitrc,.xsession,.xprofile}
        /etc/skel/{.xinitrc,.xsession,.xprofile}
    )

    local xx

    for xx in ${_files_to_remove[*]}; do rm -rf $xx; done

    find /usr/lib/initcpio -name archiso* -type f -exec rm '{}' \;

}

_clean_offline_packages(){
 local _packages_to_remove=( 
        epiphany
)
    local xx
    # @ does one by one to avoid errors in the entire process
    # * can be used to treat all packages in one command
    for xx in ${_packages_to_remove[@]}; do pacman -Rnscv $xx --noconfirm; done
}

_endeavouros(){


    sed -i "/if/,/fi/"'s/^/#/' /root/.bash_profile
    sed -i "/if/,/fi/"'s/^/#/' /home/$NEW_USER/.bash_profile

}

_check_install_mode(){

    if [ -f /tmp/run_once ] ; then
        local INSTALL_OPTION="ONLINE_MODE"
    else
        local INSTALL_OPTION="OFFLINE_MODE"
    fi

    case "$INSTALL_OPTION" in
        OFFLINE_MODE)
                _clean_archiso
                chown -R $NEW_USER:users /home/$NEW_USER/.bashrc
                _sed_stuff
                _clean_offline_packages
                _check_internet_connection && update-mirrorlist
            ;;

        ONLINE_MODE)
                # not implemented yet. For now run functions at "SCRIPT STARTS HERE"
                :
                # all systemd are enabled - can be specific offline/online in the future
            ;;
        *)
            ;;
    esac
}

_remove_ucode(){
    local ucode="$1"
    pacman -Q $ucode >& /dev/null && {
        pacman -Rsn $ucode --noconfirm >/dev/null
    }
}

_remove_other_graphics_drivers() {
    local graphics="$(device-info --vga ; device-info --display)"
    local amd=no

    # remove Intel graphics driver if it is not needed
    if [ -z "$(echo "$graphics" | grep "Intel Corporation")" ] ; then
        _remove_pkgs_if_installed xf86-video-intel
    fi

    # remove AMD graphics driver if it is not needed
    if [ -n "$(echo "$graphics" | grep "Advanced Micro Devices")" ] ; then
        amd=yes
    elif [ -n "$(echo "$graphics" | grep "AMD/ATI")" ] ; then
        amd=yes
    elif [ -n "$(echo "$graphics" | grep "Radeon")" ] ; then
        amd=yes
    fi
    if [ "$amd" = "no" ] ; then
        _remove_pkgs_if_installed xf86-video-amdgpu xf86-video-ati
    fi
}

_add_mkinitcpio_graphics_drivers() {
    local amd=no
    local amd2=no
    local intel=no

    # remove AMD graphics driver if it is not needed
    if [ -n "$(echo "$graphics" | grep "Advanced Micro Devices")" ] ; then
        amd=yes
    elif [ -n "$(echo "$graphics" | grep "AMD/ATI")" ] ; then
        amd=yes
    elif [ -n "$(echo "$graphics" | grep "Radeon")" ] ; then
        amd=yes
    fi
    if [ "$amd" = "yes" ] ; then
        sed -i 's/MODULES=\"\"/MODULES=\"amdgpu radeon\"/g' /etc/mkinitcpio.conf
        amd2=yes
    fi
    
    
    
    # remove Intel graphics driver if it is not needed
    if [ -z "$(echo "$graphics" | grep "Intel Corporation")" ] ; then
        intel=no
    else
        sed -i 's/MODULES=\"\"/MODULES=\"i915\"/g' /etc/mkinitcpio.conf
        amd2=yes
    fi
    
    
    if [ -z "$(device-info --vga | grep NVIDIA)" ] || [ -z "$(lspci -k | grep -PA3 'VGA|3D' | grep "Kernel driver in use" | grep nvidia)" ] ; then
        xx="$(pacman -Qqs nvidia* | grep ^nvidia)"
    else
        sed -i 's/MODULES=\"\"/MODULES=\"nvidia nvidia_modeset nvidia_uvm nvidia_drm\"/g' /etc/mkinitcpio.conf
        amd2=yes
    fi
    
    
    if [ "$amd2" = "no" ] ; then
        if [ -z "$(lspci -k | grep -PA3 'VGA|3D' | grep "Kernel driver in use" | grep vboxvideo)" ] ; then
            sed -i 's/MODULES=\"\"/MODULES=\"nouveau\"/g' /etc/mkinitcpio.conf
        else
            sed -i 's/MODULES=\"\"/MODULES=\"vboxvideo\"/g' /etc/mkinitcpio.conf
        fi
    fi
}

_remove_broadcom_wifi_driver() {
    local pkgname=broadcom-wl-dkms
    local wifi_pci
    local wifi_driver

    _is_pkg_installed $pkgname && {
        wifi_pci="$(lspci -k | grep -A4 " Network controller: ")"
        if [ -n "$(lsusb | grep " Broadcom ")" ] || [ -n "$(echo "$wifi_pci" | grep " Broadcom ")" ] ; then
            return
        fi
        wifi_driver="$(echo "$wifi_pci" | grep "Kernel driver in use")"
        if [ -n "$(echo "$wifi_driver" | grep "in use: wl$")" ] ; then
            return
        fi
        _remove_a_pkg $pkgname
    }
}

_clean_up(){
    local xx

    # Remove the "wrong" microcode.
    if [ -x /usr/bin/device-info ] ; then
        case "$(/usr/bin/device-info --cpu)" in
            GenuineIntel) _remove_ucode amd-ucode ;;
            *)            _remove_ucode intel-ucode ;;
        esac
    fi

    # Fix generation by grub-mkconfig.
    if [ -x /usr/bin/grub-fix-initrd-generation ] ; then
            /usr/bin/grub-fix-initrd-generation
    fi

    # remove nvidia driver if: 1) no nvidia card, 2) nvidia driver not in use (older nvidia cards use nouveau)
    # (maybe the latter alone is enough...)
    if [ -z "$(device-info --vga | grep NVIDIA)" ] || [ -z "$(lspci -k | grep -PA3 'VGA|3D' | grep "Kernel driver in use" | grep nvidia)" ] ; then
        xx="$(pacman -Qqs nvidia* | grep ^nvidia)"
        test -n "$xx" && pacman -Rsn $xx --noconfirm >/dev/null
    fi

    # remove AMD and Intel graphics drivers if they are not needed
    _remove_other_graphics_drivers

    # remove broadcom-wl-dkms if it is not needed
    _remove_broadcom_wifi_driver
}

_desktop_openbox(){
    # openbox configs here
    # Note: variable 'desktop' from '_another_case' is visible here too if more details are needed.
    
    mmaker -vf OpenBox3 # for root
    sudo -H -u $NEW_USER bash -c 'mmaker -vf OpenBox3' # for normal user

}

_desktop_i3(){
    # i3 configs here
    # Note: variable 'desktop' from '_another_case' is visible here too!

    git clone https://github.com/endeavouros-team/i3-EndeavourOS.git
    pushd i3-EndeavourOS >/dev/null
    cp -R .config /home/$NEW_USER/
    cp -R .config ~/                                                    
    chmod -R +x ~/.config/i3/scripts /home/$NEW_USER/.config/i3/scripts
    cp .Xresources ~/
    cp .Xresources /home/$NEW_USER/
    cp .gtkrc-2.0 ~/
    cp .gtkrc-2.0 /home/$NEW_USER/
    chown -R $NEW_USER:users /home/$NEW_USER/.config /home/$NEW_USER/.Xresources
    popd >/dev/null
    rm -rf i3-EndeavourOS
}

_de_wm_config(){
    local desktops_lowercase="$(ls -1 /usr/share/xsessions/*.desktop | tr '[:upper:]' '[:lower:]' | sed -e 's|\.desktop$||' -e 's|^/usr/share/xsessions/||')"
    local desktop
    local i3_added=no # break for loop
    local openbox_added=no # break for loop

    for desktop in $desktops_lowercase ; do
        case "$desktop" in
            i3*)
                if [ "$i3_added" = "no" ] ; then
                    i3_added=yes
                    _desktop_i3 
                fi
                ;;
            openbox*)
                if [ "$openbox_added" = "no" ] ; then
                    openbox_added=yes
                    _desktop_openbox
                fi
                ;;
        esac
    done
}

########################################
########## SCRIPT STARTS HERE ##########
########################################

_check_install_mode
_common_systemd
_endeavouros
_vbox
_vmware
_de_wm_config
_add_mkinitcpio_graphics_drivers
systemctl -f enable lightdm-plymouth.service
plymouth-set-default-theme -R arch-charge
systemctl enable lightdm 2>>/dev/null
systemctl start lightdm
pacman -R xfce4-screensaver --noconfirm
pacman -R calamares_current --noconfirm
pacman -R orage --noconfirm
rm -f /usr/share/desktop-directories/wps-office.directory
systemctl -f enable bluetooth.service
_clean_up

rm -rf /usr/bin/{calamares_switcher,cleaner_script.sh,chrooted_cleaner_script.sh,calamares_for_testers}

#xinit
#xfce4-session

#XDG_MENU_PREFIX="xfce-"
#export XDG_MENU_PREFIX

#DESKTOP_SESSION="xfce"
#export DESKTOP_SESSION

#XDG_CURRENT_DESKTOP="XFCE"
#export XDG_CURRENT_DESKTOP

#export XDG_SESSION_TYPE='X11' 

dbus-launch dconf load / < /etc/skel/.dconf/plank.dconf
sudo -H -u $NEW_USER bash -c 'dbus-launch dconf load / < /etc/skel/.dconf/plank.dconf'

systemctl enable --now snapd.seeded.service
systemctl enable --now snapd.socket
#systemctl daemon-reload
ln -s /var/lib/snapd/snap /snap

#snap ack /usr/share/snap-packages/snap-store/core18_1754.assert
#snap install /usr/share/snap-packages/snap-store/core18_1754.snap

#snap ack /usr/share/snap-packages/snap-store/gnome-3-28-1804_116.assert
#snap install /usr/share/snap-packages/snap-store/gnome-3-28-1804_116.snap

#snap ack /usr/share/snap-packages/snap-store/gtk-common-themes_1506.assert
#snap install /usr/share/snap-packages/snap-store/gtk-common-themes_1506.snap

#snap ack /usr/share/snap-packages/snap-store/snap-store_415.assert
#snap install /usr/share/snap-packages/snap-store/snap-store_415.snap

cp /usr/share/libertyos/unicode.pf2 /boot/grub/fonts/unicode.pf2

#rm /var/cache/fontconfig/*
#rm ~/.cache/fontconfig/*

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

#export SHELL=/bin/bash
#COLORTERM=truecolor
#export XDG_CONFIG_DIRS=/etc/skel/.config/xfce4:/etc/xdg
#export XDG_SESSION_PATH=/org/freedesktop/DisplayManager/Session0
#export XDG_MENU_PREFIX=xfce-
#LC_ADDRESS=de_AT.UTF-8
#LC_NAME=de_AT.UTF-8
#SSH_AUTH_SOCK=/tmp/ssh-yBEgovH4JnXX/agent.885
#export DESKTOP_SESSION=xfce
#LC_MONETARY=de_AT.UTF-8
#export SSH_AGENT_PID=886
#export NO_AT_BRIDGE=1
#GTK_MODULES=canberra-gtk-module:canberra-gtk-module
#export XDG_SEAT=seat0
#PWD=/home/a
#LOGNAME=a
#export XDG_SESSION_DESKTOP=xfce
#QT_QPA_PLATFORMTHEME=qt5ct
#export XDG_SESSION_TYPE=x11
#export PANEL_GDK_CORE_DEVICE_EVENTS=0
#export XAUTHORITY=/home/$NEW_USER/.Xauthority
#export XDG_GREETER_DATA_DIR=/var/lib/lightdm-data/$NEW_USER
#export HOME=/home/$NEW_USER
#export LC_PAPER=de_AT.UTF-8
#LANG=de_AT.UTF-8
#export XDG_CURRENT_DESKTOP=XFCE
#VTE_VERSION=6002
#export XDG_SEAT_PATH=/org/freedesktop/DisplayManager/Seat0
#export XDG_SESSION_CLASS=user
#export IBUS_DISABLE_SNOOPER=1
#TERM=xterm-256color
#LC_IDENTIFICATION=de_AT.UTF-8
#export USER=$NEW_USER
#DISPLAY=:0.0
#export SHLVL=1
#LC_TELEPHONE=de_AT.UTF-8
#LC_MEASUREMENT=de_AT.UTF-8
#export XDG_VTNR=7
#export XDG_SESSION_ID=2
#MOZ_PLUGIN_PATH=/usr/lib/mozilla/plugins
#export XDG_RUNTIME_DIR=/run/user/1001
#LC_TIME=de_AT.UTF-8
#export XDG_DATA_DIRS=/usr/local/share:/usr/share:/var/lib/snapd/desktop:/usr/share
#BROWSER=firefox
#PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:/var/lib/snapd/snap/bin
#export GDMSESSION=xfce
#DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus
#MAIL=/var/spool/mail/a
#LC_NUMERIC=de_AT.UTF-8
