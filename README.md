AWS Web Infrastructure Terraform Project
Overview

This repository contains Terraform code to provision a basic AWS web server infrastructure, including:

    VPC with public subnet

    Internet Gateway and Route Tables

    Security groups for web (HTTP/HTTPS) and SSH access

    Elastic IP for static public IP

    EC2 instance running a web server (Apache)

Prerequisites

    AWS Account with proper permissions for provisioning VPC, EC2, etc.

    Terraform installed (tested with version 1.12.2)

    AWS CLI configured or environment variables set for credentials (do NOT hardcode credentials in files)
