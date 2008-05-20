#! /bin/bash
ifconfig ath0 down ;
wlanconfig ath0 destroy ;
rmmod ath_pci ;
rmmod ath_rate_amrr ;
rmmod ath_rate_sample ; 
rmmod ath_rate_minstrel ;
rmmod wlan_scan_ap ; 
rmmod wlan_scan_sta ; 
rmmod ath_hal ; 
rmmod wlan 
