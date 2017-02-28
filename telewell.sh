#!/bin/sh
# Install script by Olli Helin
# olli.helin@iki.fi
# http://www.iki.fi/Olli.Helin/

instdir="/opt/telewell"
udevdir="/lib/udev/rules.d"

if [ $(/usr/bin/id -u) -ne 0 ]
then
    echo
    echo "You do not seem to be running this script with root privileges."
    echo "If you intended so, or if you know you have the privileges, press C to continue."
    echo "Otherwise, press any other key to quit, and run the script again with root"
    echo "privileges, for example like this:"
    echo
    echo "sudo ./install.sh"
    echo
    stty raw
    input=$(dd if=/dev/tty bs=1 count=1 2>/dev/null)
    stty -raw
    if test "$input" != "C" && test "$input" != "c"
    then
        exit
    fi
    clear
fi

if test "X$(which wvdial 2>/dev/null)" = "X"
then
    echo "You seem to be missing the wvdial application. It is required for the"
    echo "automatic connection script to work. If you want to manually connect"
    echo "with a network manager application or by other means, you may continue."
    echo
    echo "It is recommended that you install wvdial before continuing."
    echo
    echo "In Ubuntu, the command for installation is: sudo apt-get install wvdial"
    echo
    echo "Press Ctrl-C to cancel installation, or <return> to continue".
    read
    clear
fi

if test "X$(which ip 2>/dev/null)" = "X"
then
    echo "You seem to be missing the ip application. It is required for the"
    echo "automatic connection script to work. If you want to manually connect"
    echo "with a network manager application or by other means, you may continue."
    echo
    echo "It is recommended that you install ip before continuing. It is a part"
    echo "of the iproute2 suite, a collection of networking utilities."
    echo
    echo "In Ubuntu, the command for installation is: sudo apt-get install iproute"
    echo
    echo "Press Ctrl-C to cancel installation, or <return> to continue".
    read
    clear
fi

if [ -d $instdir ]
then
    echo
    echo "Installation directory $instdir already exists. Press Ctrl-C to cancel"
    echo "installation, or <return> to continue and overwrite existing directory."
    echo
    echo "(If you are re-installing the driver, you may disregard this message.)"
    read
    clear
fi

echo "What is your Internet Service Provider's (ISP) Access Point Name (APN)?"
echo "Leave blank (press <return>) for default: \"internet\""
echo
echo "NOTE: If your ISP requires a username, password, or any other special"
echo "parameters, you may manually edit the file $instdir/wvdial.conf afterwards."
echo
echo -n "APN: "
read apn
if test "X$apn" = "X"
then apn="internet"
fi
clear
#echo "OPTIONAL: Would you like to enable sharing of your 3G Internet connection via"
#echo "other network adapters using iptables? Press Y to enable, any other key to skip."
#stty raw
#input=$(dd if=/dev/tty bs=1 count=1 2>/dev/null)
#stty -raw
#if test "$input" = "Y" || test "$input" = "y"
#then
#    sharingmodifier=""
#else
#    sharingmodifier="#"
#fi
#echo
#clear
sharingmodifier="#"

if [ -d $instdir ]
then rm -rf $instdir
fi

mkdir $instdir

cat > $instdir/udevhelper.sh << EOF
#!/bin/sh

# Call the real script (given as argument) and exit so that udev doesn't timeout.
$instdir/\$1 &
exit
EOF

cat > $instdir/connect.sh << EOF
#!/bin/sh

# Check if wvdial can be found.
if test "X\$(which wvdial | grep which: no)" != "X"
then exit
fi

logfile=$instdir/wvdial.log
max_wait_connection_time=30 # Wait for a maximum of this many seconds for connection to initialize.

# Wait for the modem to initialize. Ten seconds should be enough. Also, kill all wvdial processes.
killall -q wvdial
sleep 10

# Check whether we have a read-only filesystem to avoid udev errors.
testfile=\$(mktemp $instdir/XXX 2>/dev/null)
if test "X\$testfile" = "X"
then
    logfile=/dev/null
else
    rm \$testfile
fi

# Remove any default routes so that wvdial may add a new default.
defaultroute=\$(/sbin/ip route show | /bin/grep default)
if test "X\$defaultroute" != "X"
then
    /sbin/ip route del \$defaultroute
    /bin/echo "Deleted default route:" >> \$logfile
    /bin/echo "\$defaultroute" >> \$logfile
fi

# Start a new logfile with timestamp.
date > \$logfile

# Try to dial first modem device.
/bin/echo "Trying primary config..." >> \$logfile
/usr/bin/wvdial -C $instdir/wvdial.conf &>> \$logfile &
# Wait for connection for total of max_wait_connection_time seconds.
timer=0
while [ \$timer -lt \$max_wait_connection_time ]
do
    sleep 1
    # Check out if we got signal.
    if test "X\$(/sbin/ip link show ppp0 2>/dev/null | /bin/grep UP)" != "X"
    then timer=\$max_wait_connection_time
    fi
done

# Check that default route exists. If it does not, wvdial might have failed.
defaultroute=\$(/sbin/ip route show | /bin/grep default)
if test "X\$defaultroute" = "X"
then
    /bin/echo "Default route is missing!" >> \$logfile
fi

# Share connection via other network adapters.
$sharingmodifier if test "X\$(ps -e | /bin/grep wvdial)" != "X"
$sharingmodifier then
$sharingmodifier     /sbin/iptables -F; /sbin/iptables -t nat -F; /sbin/iptables -t mangle -F
$sharingmodifier     /sbin/iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE
$sharingmodifier     /sbin/sysctl -e -q -w net.ipv4.conf.ppp0.forwarding=1
$sharingmodifier     /sbin/sysctl -e -q -w net.ipv6.conf.ppp0.forwarding=1
$sharingmodifier fi
EOF

cat > $instdir/wvdial.conf << EOF
[Dialer Defaults]
Init1 = AT+CGDCONT=1,"IP","$apn"
Init2 = ATZ
Init3 = ATQ0 V1 E1 S0=0 &C1 &D2 +FCLASS=0
Stupid Mode = 1
Modem Type = Analog Modem
Phone = *99#
ISDN = 0
Username = " "
Password = " "
Modem = /dev/serial/tw_3g_hspa
Baud = 21000000
EOF

chmod +x $instdir/udevhelper.sh
chmod +x $instdir/connect.sh

cat > $udevdir/99-tw-3g-hspa.rules << EOF
# TeleWell TW-3G HSPA+

# Switch the 3G modem from CD drive state to modem state.
ACTION=="add", ATTRS{idVendor}=="1c9e", ATTRS{idProduct}=="98ff", RUN+="/usr/sbin/usb_modeswitch -v 0x1c9e -V 0x1c9e -p 0x98ff -P 0x9801 -M 55534243123456780000000080000606f50402527000000000000000000000"

# Load driver.
ACTION=="add", ENV{ID_VENDOR}=="USB_Modem", ENV{ID_MODEL}=="USB_Modem", ENV{ID_MODEL_ID}=="9801", ENV{DEVTYPE}=="usb_device", RUN+="/sbin/modprobe option", RUN+="/bin/sh -c '/bin/sleep 5 && /bin/echo 1c9e 9801 > /sys/bus/usb-serial/drivers/option1/new_id'"

# Symlink the first modem device and try to connect.
ACTION=="add", ENV{ID_VENDOR}=="USB_Modem", ENV{ID_MODEL}=="USB_Modem", ENV{ID_MODEL_ID}=="9801", ENV{ID_USB_INTERFACE_NUM}=="01", ENV{ID_USB_DRIVER}="usbserial", SYMLINK="serial/tw_3g_hspa", RUN+="$instdir/udevhelper.sh connect.sh"
EOF

clear
echo "Installed:"
echo " $instdir/udevhelper.sh"
echo " $instdir/connect.sh"
echo " $instdir/wvdial.conf"
echo " $udevdir/99-tw-3g-hspa.rules"
echo
echo "Installation complete!"
echo
echo "From now on you will be automatically connected to the Internet when you"
echo "plug in your TW-3G HSPA+, or if it is already connected on boot."
echo
echo "You must now restart your udev service, or simply reboot your computer."
echo

