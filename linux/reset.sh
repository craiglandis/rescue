#!/bin/bash
#
# Vittorio Franco Libertucci 
# May 2015
#######
# v1.0
# Requires VM extensions
# Script check if the ssh process is running 
# Restarts ssh and tests again
# If still no success will make backup of  sshd and download clean copy 
# Next turn off firewall 
# Collect data processes, network, mounted disks
###################################################

                
location="https://azuresupport.blob.core.windows.net/linux/"
destination=/etc/ssh/sshd_config

#########################
#                       #  
# Verify distro         #
#                       #
#########################

which python  > /dev/null 2>&1
python_status=`echo $?`  

#echo $python_status

timest=`date +%d-%h-%Y_%H:%M:%S`

if [ "${python_status}" -eq 0 ];  then
#       echo "python is installed"
        distro=`python -c 'import platform ; print platform.dist()[0]'`
        
		date
        echo "VM `uname -n` - Linux distro" $distro
                echo "                    ."
else
        distro=$(awk '/DISTRIB_ID=/' /etc/*-release | sed 's/DISTRIB_ID=//' | tr '[:upper:]' '[:lower:]')

echo $distro
fi

#####


if [ "${distro}" = "Ubuntu" ]; then
        osver=`grep -i version_id /etc/os-release`
             if [ $osver = VERSION_ID=\"12.04\" ]; then
                        echo "OS = $osver"
                        sshrestart="service ssh start"
                        file=sshd_config_ubuntu12
                
                elif [ $osver = VERSION_ID=\"14.04\" ] || [ $osver = VERSION_ID=\"14.10\" ] ;then
                        echo "OS = $osver"
                        sshrestart="initctl --system start ssh"
						sshrestart2="initctl --system restart ssh"
                        file=sshd_config_ubuntu14
 
             fi

elif [ "${distro}" = "SuSE" ]; then

        osver=`grep -i version /etc/SuSE-release|awk '{print $3}'`

            if [ $osver = 11 ]; then
                echo "OS = $osver"
                sshrestart="service sshd start"
                file=sshd_config_sles11
                
        elif [ $osver = 12 ] ;then
                echo "OS = $osver"
                sshrestart="/usr/bin/systemctl start sshd"
                file=sshd_config_sles12

             fi
#fi

echo "distro is " $distro
#centos

elif [[ "${distro}" = "centos"  && -e /etc/os-release ]]; then 
        osver=`grep -i version_id /etc/os-release|awk -F'"' '{print $2}'`;echo $osver
        echo "this is centos" $osver

        if [ $osver = "7" ]; then
                echo "OS = $osver"
                sshrestart="/bin/systemctl start sshd"
                file=sshd_config_centos7
        fi

elif [[ "${distro}" = "centos"  && ! -e /etc/os-release ]]; then
        osver=`grep -i release /etc/centos-release|awk -F' ' '{print $3}'`;echo $osver
        echo "this is centos" $osver
if [ $osver = 6.6 ] || [ $osver = 6.5 ] || [ $osver = 6.6 ] || [ $osver = 6.7 ]; then
                echo "OS = $osver"
                sshrestart="service sshd restart"
                file=sshd_config_centos66
                
        fi


elif [[ "${distro}" = redhat && -e /etc/redhat-release ]]; then
        osver=`grep -i release /etc/redhat-release|awk -F' ' '{print $7}'`;echo $osver
        echo "this is centos" $osver
if [ $osver = 6.6 ] || [ $osver = 6.5 ] || [ $osver = 6.6 ] || [ $osver = 6.7 ]; then
             echo "OS = $osver"
             sshrestart="service sshd restart"
             file=sshd_config_centos66
        fi
else
echo "Distro $distro currently not tested"
exit
fi

####
#Get IP address
ipa=`hostname -i`

        echo "1st pass - testing ssh connection"
        #echo "" | curl -v telnet://127.0.0.1:22 &>/dev/null
        echo "" | curl -v telnet://$ipa:22 &>/dev/null

        if [ "$?" -eq 0 ];  then
                 echo "1st Pass - Connected successfully to ssh" 
        else 

                echo "1st Pass - failed Could not connect locally to ssh"
                echo ".            Restarting ssh                             ."
        
                $sshrestart 2> /dev/null
				$sshrestart2 2> /dev/null
                sleep 5

                # Test sshd config possibly
                #/usr/sbin/sshd -t -f /etc/ssh/sshd_config &> /dev/null;rc=$?
                # test the $rc variable should be 0 for good config

                echo "2nd Pass - Testing ssh connection"
               #echo "" | curl -v telnet://127.0.0.1:22 &>/dev/null
        	echo "" | curl -v telnet://$ipa:22 &>/dev/null

                        if [ "$?" -eq 0 ];  then
                                echo " test 2 Connected successfully to ssh"
                        else 

                                #Copying sshd_config from working
                                echo "test 2 failed to connect to ssh after restarting - downloading new sshd_config"

                                if [ -e /etc/ssh/sshd_config ]; then cp -f $destination $destination"_"$timest;
                                curl $location$file -o $destination
                                fi
        
                                #curl https://azuresupport.blob.core.windows.net/linux/sshd_config_centos66 -o /etc/ssh/sshd_config
                                curl $location$file -o $destination
                                chmod 600 $destination

                                #echo ".                    Restarting ssh                             ."
                                #service sshd restart
                                $sshrestart
								$sshrestart2 2> /dev/null
                                sleep 4

                                echo "3rd Pass - Testing ssh connection"
                                #echo "" | curl -v telnet://127.0.0.1:22 &>/dev/null
                                echo "" | curl -v telnet://$ipa:22 &>/dev/null

 
                                        if [ "$?" -eq 0 ];  then
                                        echo " test 3 Connected successfully to ssh"
                                        else
                                        echo "3rd past of local ssh connection failed"

       fi
     fi
   fi

#echo look for top processes
echo "                         #"
echo "top processes"
top -n1 -b | head -20

echo "                         #"
echo "turn off firewall"
#Turn off the firewall
$firewallstop

echo "                         #"
echo "Some networking checks"

#Check networking 
ifconfig -a
netstat -rn

echo "                         #"
time nslookup www.microsoft.com

echo "                         #"
df -h

#echo "                        #"
#cat /etc/fstab

