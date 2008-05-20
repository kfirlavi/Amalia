#! /bin/bash
ifconfig ath0 down
wlanconfig ath0 destroy ;
rmmod ath_pci ;
rmmod ath_rate_amrr ;
rmmod ath_rate_sample ;
rmmod ath_rate_minstrel ;
rmmod wlan_scan_ap ;
rmmod wlan_scan_sta ;
rmmod ath_hal ;
rmmod wlan ;
insmod test_drivers/ath_hal.ko ;
insmod test_drivers/wlan.ko ;
insmod test_drivers/ath_rate_amrr.ko ;
#insmod test_drivers/ath_rate_sample.ko
#insmod test_drivers/ath_rate_minstrel.ko
#insmod test_drivers/wlan_scan_ap.ko ;
insmod test_drivers/wlan_scan_sta.ko ;
insmod test_drivers/ath_pci.ko ratectl=amrr autocreate=none &&
wlanconfig ath0 create wlandev wifi0 wlanmode sta &&
iwconfig ath0 rate 11Mb essid "AGGNET"
ifconfig ath0 inet 172.16.1.100 netmask 255.255.0.0 up &&
iwconfig ath0 &&
ifconfig ath0 &&
ifconfig wifi0 
iwpriv ath0 abolt 0
