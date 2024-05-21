#!/usr/bin/env bash

# Define the ASCII art
cat << "EOF"
************************************************************************
 __    ___    ______    __      __    ______     _____     __     _____
|  \  |   |  |   ___|  |  \    /  |  |   ___|   /  ___|   |  |   /  ___|
|   \ |   |  |  |__    |   \  /   |  |  |__    |  |___    |  |  |  |___
|   |\|   |  |   __|   |   |\/|   |  |   __|    \__   \   |  |   \__   \
|   | \   |  |  |___   |   |  |   |  |  |___     ___\  |  |  |    ___\  |
|___|  \__|  |______|  |___|  |___|  |______|   |_____/   |__|   |_____/

************************************************************************
EOF

# Rest of the script goes here

# Let's set variables for the repository and the IP address of the server
GIT_REPO=""

# Let's ask the user which installation method he wants to use

# Install necessary packages
if command -v dnf &> /dev/null; then
  sudo dnf update -y && sudo dnf install -y git
elif command -v apt-get &> /dev/null; then
  sudo apt update -y && sudo apt install -y git
else
  echo "Unsupported package manager. Exiting."
fi

echo "Choose the installation method: "
echo "1. Ansible"
echo "2. Kubernetes"
read -p "Enter 1 or 2: " INSTALL_METHOD

# Install necessary packages
if command -v dnf &> /dev/null; then
  sudo dnf update -y && sudo dnf install -y git
elif command -v apt-get &> /dev/null; then
  sudo apt update -y && sudo apt install -y git
else
  echo "Unsupported package manager. Exiting."
fi

 # If the user has chosen to install via Ansible
  git clone $GIT_REPO

if [ "$INSTALL_METHOD" == "1" ]; then 

 # Install necessary packages for Ansible
  if command -v dnf &> /dev/null; then
    sudo dnf install -y nano python3.11 python3.11-pip sshpass
  elif command -v apt-get &> /dev/null; then
    sudo apt install -y nano python3 python3-pip sshpass
  fi

  sudo nano -w ./nemesis-ansible/environment/template/hosts  

  export PATH=$PATH:/usr/local/bin

  if command -v dnf &> /dev/null; then
    sudo pip3.11 install ansible && sudo pip3.11 install --upgrade ansible && sudo pip3.11 install --force-reinstall ansible
  elif command -v apt-get &> /dev/null; then
    sudo pip3 install ansible && sudo pip3 install --upgrade ansible && sudo pip3 install --force-reinstall ansible
  fi
  
  ansible-vault decrypt ./nemesis-ansible/environment/template/group_vars/all.yml
  sudo nano -w ./nemesis-ansible/environment/template/group_vars/all.yml
  sudo nano -w ./nemesis-ansible/deploy.yaml

  ansible-galaxy collection install community.docker --force
  ansible-galaxy collection install community.general --force
  
  read -p "Do you have an Internet connection? Do you want to install Docker images? (yes/no/skip): " answer
  read -p "Set Deployment Profile (reshenie, mtbank, belincas): " profile
  
  if [ "$answer" = "yes" ]; then
        if command -v dnf &> /dev/null; then
            echo "Installing Docker images..."
            sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine podman runc
            if ! grep -q "download.docker.com" /etc/yum.repos.d/*.repo; then
                # Adding a Docker repository
                sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
                echo "Docker repository added successfully."
            else
                echo "Docker repository already exists."
            fi
            sudo dnf install -y docker-ce docker-ce-cli containerd.io && sudo usermod -aG docker $USER && sudo systemctl enable docker && sudo systemctl start docker
            sudo sh ./nemesis-ansible/scripts/add_images.sh
        elif command -v apt-get &> /dev/null; then
            echo "Installing Docker images..."
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common lsb-release

                REPO_URL="https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

                # Checking the existence of a Docker repository
            if ! grep -q "^deb.*$REPO_URL" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
                # Adding a Docker repository
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
                sudo add-apt-repository "deb [arch=amd64] $REPO_URL"
                echo "Docker repository added successfully."
            else
                echo "Docker repository already exists."
            fi
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            sudo usermod -aG docker $USER
            sudo systemctl enable docker
            sudo systemctl start docker
            sudo sh ./nemesis-ansible/scripts/add_images.sh
        fi
  elif [ "$answer" = "no" ]; then
    echo -e "Upload docker images to the nemesis-ansible/scripts/IMAGES/ folder.\n\n"
    echo "After that, run the command: ansible-playbook -i ./nemesis-ansible/environment/template/hosts ./nemesis-ansible/deploy.yaml"
    exit 0
  elif [ "$answer" = "skip" ]; then
     echo "Install ..."
  fi

  if [ -f nemesis_back.tar.gz ]; then
    # Transfer the file to the specified folder
    mv nemesis_back.tar.gz ./nemesis-ansible/scripts/IMAGES/
  fi
  if [ -f nemesis_front.tar.gz ]; then
    # Unzip the file
    tar -xzvf nemesis_front.tar.gz
    cp -rf nemesis-front-$profile/* ./nemesis-ansible/roles/nginx/files/nemesis/
  fi

  read -p "Enter servers ip from the project: " servers_ip

  echo "Generating ssh keys"
  ssh-keygen

  read -p "Enter user name for remote server: " servers_name

  for ip in $servers_ip; do
    ssh-copy-id $servers_name@$ip
  done
  ansible all -i ./nemesis-ansible/environment/template/hosts -m shell -a "echo 'sysops ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/sysops" --ask-become-pass

  ansible-playbook -i ./nemesis-ansible/environment/template/hosts ./nemesis-ansible/deploy.yaml --ask-become-pass

# If the user has chosen to install via Kubernetes
elif [ "$INSTALL_METHOD" == "2" ]; then

# Check if the file /etc/redhat-release exists
if [ -f /etc/redhat-release ]; then
    # Disable SELinux0
    sudo setenforce 0
    sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

    # Disable Swap
    sudo swapoff -a
    sudo sed -i '/swap/d' /etc/fstab

    # Disable Firewall (firewalld)
    sudo systemctl stop firewalld
    sudo systemctl disable firewalld

    echo "SELinux, Swap, and Firewall successfully disabled."
else
    echo "This script is intended for Red Hat-based systems. Exiting."
fi

  # Install necessary packages for Kubernetes setup
  if command -v dnf &> /dev/null; then
    sudo dnf install -y oracle-epel-release-el8
    sudo dnf install -y git sshpass python3 python3-pip    
  elif command -v apt-get &> /dev/null; then
    sudo apt-get install -y git sshpass python3 python3-pip
  fi
  
  # If the user has chosen to install via Kubernetes
  git clone https://github.com/kubernetes-sigs/kubespray.git  
  sudo dnf install python3.11 python3.11-pip && sudo pip3.11 install -r ./kubespray/requirements.txt

  read -p "Enter the kubeclaster name: " cluster_name

  cp -rfp ./kubespray/inventory/sample ~/kubespray/inventory/${cluster_name}
  # Entering a username and password

  read -p "Enter servers ip kubernetes cluster: " servers_ip

  declare -a IPS=(${servers_ip})
  CONFIG_FILE=./kubespray/inventory/${cluster_name}/hosts.yaml python3.11 ./kubespray/contrib/inventory_builder/inventory.py ${IPS[@]}
  
  sudo nano -w ./kubespray/inventory/${cluster_name}/hosts.yaml


  sudo nano -w ./kubespray/inventory/${cluster_name}/group_vars/all/all.yml
  sudo nano -w ./kubespray/inventory/${cluster_name}/group_vars/k8s_cluster/k8s-cluster.yml
  sudo nano -w ./kubespray/inventory/${cluster_name}/group_vars/k8s_cluster/addons.yml

  echo "Generating ssh keys"
  ssh-keygen

  read -p "Enter user name for remote server: " servers_name

  for ip in $servers_ip; do
    ssh-copy-id $servers_name@$ip
  done
  
  ansible all -i ./kubespray/inventory/${cluster_name}/hosts.yaml -m shell -a "echo 'sysops ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/sysops"
  ansible all -i ./kubespray/inventory/${cluster_name}/hosts.yaml -m shell -a "sudo systemctl stop firewalld && sudo systemctl disable firewalld"
  ansible all -i ./kubespray/inventory/${cluster_name}/hosts.yaml -m shell -a "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf"
  ansible all -i ./kubespray/inventory/${cluster_name}/hosts.yaml -m shell -a "sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab && sudo swapoff -a"

  cd kubespray && ansible-playbook -i inventory/${cluster_name}/hosts.yaml  --become --become-user=root cluster.yml

  kubectl create namespace nemesis-namespace
  kubectl apply -f nemesis/k8s/.

else
  echo "Wrong choice. Try again."
fi
