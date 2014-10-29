#!/bin/bash
currentUbuntuVersionSupported="14.04"

############################################################
# Functions
############################################################

# installer nickName, actualName
# example: installer best-text-editor nano
function installer
{
	if [ -z "`which "$1" 2>/dev/null`" ]
	then
		executable=$1
		shift
		while [ -n "$1" ]
		do
			DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1"
			apt-get clean
			printInfo "$1 installed for $executable"
			shift
		done
	else
		printWarn "$2 already installed"
	fi
}

# uninstaller nickName, actualName
# example: uninstaller /usr/sbin/apache2 'apache2*'
function uninstaller
{
	if [ -n "`which "$1" 2>/dev/null`" ]
	then
		DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge "$2"
		apt-get clean
		printInfo "$2 removed"
	else
		printWarn "$2 is not installed"
	fi
}

# exits script if something goes wrong
function die
{
	echo "ERROR: $1" > /dev/null 1>&2
	exit 1
}

# Green Text
function printInfo {
	echo -n -e '\e[32m'
	echo -n $1
	echo -e '\e[0m'
}

# Yellow Text
function printWarn
{
	echo -n -e '\e[93m'
	echo -n $1
	echo -e '\e[0m'
}

# Red Text
function printError
{
	echo -n -e '\e[91m'
	echo -n $1
	echo -e '\e[0m'
}

# Do some sanity checking (root and Ubuntu version)
function checkSanity
{
	if [ $(/usr/bin/id -u) != "0" ]
	then
		die 'Must be run by root user'
	fi
	. /etc/lsb-release
	version=$DISTRIB_RELEASE
	if [ "$version" != "$currentUbuntuVersionSupported" ]
	then
		die "Distribution is not supported"
	fi
}

############################################################
# Initial Setup
############################################################

function baseInstaller
{
	installer nano nano # text editor
	installer vim vim # text editor
	installer iftop iftop # show network usage
	installer nload nload # visualize network usage
	installer htop htop # task manager
	installer mc mc # file explorer
	installer unzip unzip
	installer zip zip
	installer curl curl
	installer screen screen
	installer gt5 gt5 # visual disk usage
	installer dnsutils dnsutils # dns tools
	ppaGit # verison control
}

function removeUneededPackages
{
	# Apache
	service apache2 stop
	apt-get remove apache2*
	apt-get autoremove -y
}

function setTimezone
{
	dpkg-reconfigure tzdata
}

function ppaSupport
{
	checkInstall python-software-properties python-software-properties
}

function hardenSysctl
{
	cat sysctl-append.conf >> /etc/sysctl.conf
	sysctl -p
}

function ppaGit
{
	add-apt-repository ppa:git-core/ppa -y
	apt-get update
	checkInstall git git
}

function baseSetup
{
	setTimezone
	removeUneededPackages
	runUpdater
	hardenSysctl
	ppaSupport
	baseInstaller
	runUpdater
}

############################################################
# Main options
############################################################

# Nginx/PHP
function installWWW
{
	# PHP
	# https://www.digitalocean.com/community/tutorials/how-to-install-linux-nginx-mysql-php-lemp-stack-on-ubuntu-14-04
	checkInstall php5-fpm php5-fpm
	checkInstall php5-mysql php5-mysql
	sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php5/fpm/php.ini
	service php5-fpm restart

	# Nginx/Pagespeed from source

}

# MariaDB
function installMariadb
{
	checkInstall software-properties-common software-properties-common
	apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db
	add-apt-repository 'deb http://mirror.stshosting.co.uk/mariadb/repo/10.0/ubuntu trusty main'
	apt-get update
	checkInstall mariadb-server mariadb-server
	service mysql start
	printInfo "Respond YES to all questions asked to secure your MariaDB install"
	mysql_secure_installation
}

# UFW
function installUfw
{
	checkInstall ufw ufw

	if [ -z "$1" ]
	then


		die "Usage: `basename $0` ufw [ssh-port-#]"
	fi

	# Reconfigure sshd - change port
	sed -i 's/^Port [0-9]*/Port '$1'/' /etc/ssh/sshd_config
    service ssh restart

	ufw disable
	ufw default allow outgoing
	ufw default deny incoming
	ufw allow http
	ufw allow https
	ufw allow $1
	ufw enable
}

############################################################
# Commands
############################################################

# permissions
function wwwPermissions
{
	if [ -z "$1" ]
	then
		chown -R deploy:deploy /sites
		print_info "User deploy is now the owner of the www directory"
	else
		chown -R $1:$1 /sites
		print_info "User $1 is now the owner of the www directory"
	fi
}

# updater
function runUpdater
{
	for i in 1 2
	do
		apt-get -q -y update
		apt-get -q -y upgrade
		apt-get -q -y dist-upgrade
		# clean up
		apt-get -q -y autoremove
		apt-get -q -y autoclean
		apt-get -q -y clean
	done
}

# test
function runTests
{
	printInfo "Classic I/O test"
	printInfo "dd if=/dev/zero of=iotest bs=64k count=16k conv=fdatasync && rm -fr iotest"
	dd if=/dev/zero of=iotest bs=64k count=16k conv=fdatasync && rm -fr iotest

	printInfo "Network test"
	printInfo "wget cachefly.cachefly.net/100mb.test -O 100mb.test && rm -fr 100mb.test"
	wget cachefly.cachefly.net/100mb.test -O 100mb.test && rm -fr 100mb.test
}

# locale
function fixLocale
{
	checkInstall multipath-tools multipath-tools
	export LANGUAGE=en_US.UTF-8
	export LANG=en_US.UTF-8
	export LC_ALL=en_US.UTF-8
	# Generate locale
	locale-gen en_US.UTF-8
	dpkg-reconfigure locales
}

# ip
# script compatible with NATed servers.
function getIp
{
	IP=$(wget -qO- ipv4.icanhazip.com)
	if [ "$IP" = "" ]; then
    	IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}')
	fi
	echo $IP
}

# harden-ssh [option #]

# www-restart
function wwwRestart
{
	service php5-fpm restart
	service nginx restart
}

# info
function osInfo
{
	# Thanks for Mikel (http://unix.stackexchange.com/users/3169/mikel) for the code sample which was later modified a bit
	# http://unix.stackexchange.com/questions/6345/how-can-i-get-distribution-name-and-version-number-in-a-simple-shell-script
	ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')

	. /etc/lsb-release
	OS=$DISTRIB_ID
	VERSION=$DISTRIB_RELEASE

	OS_SUMMARY=$OS
	OS_SUMMARY+=" "
	OS_SUMMARY+=$VERSION
	OS_SUMMARY+=" "
	OS_SUMMARY+=$ARCH
	OS_SUMMARY+="bit"

	printInfo "$OS_SUMMARY"
}

# fail2ban
function fail2banInstall {
	checkInstall fail2ban fail2ban
	cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
	service fail2ban restart
	printWarn "Fail2ban's config file is located in /etc/fail2ban/jail.local"

}

########################################################################
# Start of script
########################################################################

checkSanity
case "$1" in
# main options
setup)
	baseSetup
	;;
firewall)
	installUfw $2
	;;
www)
	installWWW
	;;
mariadb)
	installMariadb
	;;
# other options/custom commands
harden-ssh)
	hardenSsh $2
	;;
www-permissions)
	wwwPermissions $2
	;;
www-restart)
	wwwRestart
	;;
fail2ban)
	fail2banInstall
	;;
info)
	osInfo
	;;
ip)
	getIp
	;;
updater)
	runUpdater
	;;
locale)
	fixLocale
	;;
test)
	runTests
	;;
*)
	osInfo
	echo '  '
	echo 'Usage:' `basename $0` '[option] [argument]'
	echo '  '
	echo 'Main options (in recomended order):'
	echo '  - setup                  (Remove unneeded, upgrade system, install software)'
	echo '  - ufw [port]             (Setup basic firewall with HTTP(S) and SSH open)'
	echo '  - www                    (Install Ngnix, PHP, and Pagespeed)'
	echo '  - mariadb                (Install MySQL alternative and set root password)'
	echo '  '
	echo 'Extra options and custom commands:'
	echo '  - www-permissions        (Make sure the proper permissions are set for /var/www/)'
	echo '  - www-restart            (Restarts Ngnix and PHP)'
	echo '  - harden-ssh [option #]  (Hardens openSSH with PermitRoot and PasswordAuthentication)'
	echo '  - fail2ban               (Installs fail2ban and creates a config file)'
	echo '  - info                   (Displays information about the OS, ARCH and VERSION)'
	echo '  - ip                     (Displays the external IP address of the server)'
	echo '  - updater                (Updates/upgrades packages, no release upgrades)'
	echo '  - locale                 (Fix locales issue with OpenVZ Ubuntu templates)'
	echo '  - test                   (Run the classic disk IO and classic cachefly network test)'
	echo '  '
	;;
esac
