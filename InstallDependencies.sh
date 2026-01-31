#!/bin/bash

if ! command -v route &>/dev/null; then
    echo "net-tools is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y net-tools
    echo "net-tools installed successfully!"
fi

if ! command -v jq &>/dev/null; then
    echo "jq is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y jq
    echo "jq installed successfully!"
fi

if ! command -v sshpass &>/dev/null; then
    echo "sshpass is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y sshpass
    echo "sshpass installed successfully!"
fi

if ! command -v autossh &>/dev/null; then
    echo "autossh is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y autossh
    echo "autossh installed successfully!"
fi

if ! command -v proxychains4 &>/dev/null; then
    echo "proxychains4 is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y proxychains4
    echo "proxychains4 installed successfully!"
fi