#!/bin/bash
# 192.168.1.10 your WSL2 fixed address outside of DHCP / 192.168.1.1 your router address
#sudo ip addr flush eth0 && sudo ip addr add 192.168.103.10/24 brd + dev eth0 && sudo ip route delete default; sudo ip route add default via 192.168.103.1
#sudo ip addr flush eth0 && sudo ip addr add $1 brd + dev eth0 && sudo ip route delete default; sudo ip route add default via $2
sudo ip addr add $1 brd + dev eth0 label eth0:1; sudo ip route add default via $2
# run docker deamon and enjoy your hassle free containers.
#sudo dockerd

