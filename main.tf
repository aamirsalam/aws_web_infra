
# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}



resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    name = "Production VPC"
  }
}



resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id

  tags = {
    Name = "prod-gw"
  }
}

resource "aws_egress_only_internet_gateway" "egress_ipv6" {
  vpc_id = aws_vpc.prod-vpc.id
}


resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.egress_ipv6.id
  }

  tags = {
    Name = "example"
  }
}



resource "aws_subnet" "prod-subnet" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Prod subnet"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.prod-subnet.id
  route_table_id = aws_route_table.prod-route-table.id
}


#security group

resource "aws_security_group" "allow_web" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  tags = {
    Name = "allow_web"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = aws_vpc.prod-vpc.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

# resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv6" {
#   security_group_id = aws_security_group.allow_web.id
#   cidr_ipv6         = aws_vpc.prod-vpc.ipv6_cidr_block
#   from_port         = 80
#   ip_protocol       = "tcp"
#   to_port           = 80
# }

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ssh" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0" # Or restrict to your IP for better security
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

# Add this to allow HTTP traffic
resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}


#Network Interface

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.prod-subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

}

#Elastic IP. Has a depends on flag with IGW; set depends_on flag with IGW.

resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

#Create EC2 instance

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}


resource "aws_instance" "my_first_server" {
  #ami               = "ami-00ca32bbc84273381" # Amazon Linux 2 AMI (HVM), SSD Volume Type - us-east-1
  ami               = data.aws_ami.amazon_linux_2.id
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "aamir_ec2"
  depends_on        = [aws_eip.one]


  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
    #!/bin/bash

    #------------- wait for network -----------------
    MAX_RETRIES=20
    RETRY_COUNT=0
    until ping -c 1 amazon.com; do
      echo "Waiting for network connectivity..."
      sleep 5
      RETRY_COUNT=$((RETRY_COUNT+1))
      if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        echo "Network check failed after $MAX_RETRIES attempts, continuing anyway."
        break
      fi
    done

    #------------- log everything -------------------
    exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

    #------------- allow system to settle -----------
    echo "[$(date)] Waiting for system to initialize..."
    sleep 120

    #------------- wait for yum lock ---------------
    echo "[$(date)] Checking yum lock..."
    while [ -f /var/run/yum.pid ]; do
      echo "[$(date)] Waiting for yum lock to clear..."
      sleep 10
    done

    #------------- install Apache -------------------
    echo "[$(date)] Installing httpd..."
    until yum install -y httpd; do
      echo "[$(date)] Retrying httpd installation..."
      sleep 10
    done

    echo "[$(date)] Starting and enabling httpd..."
    systemctl start httpd
    systemctl enable httpd

    echo "[$(date)] Creating index.html..."
    echo "<h1>Hello from AWS $(hostname)</h1>" > /var/www/html/index.html

    echo "[$(date)] User-data script completed"
  EOF

  tags = {
    Name = "web-server"
  }
}
