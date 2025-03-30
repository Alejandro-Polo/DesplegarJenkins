provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "my_vpc" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "public_subnet" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = { Name = "gw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "public_rt" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "web_sg" {
  name_prefix = "terraform-"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "jenkins" {
  ami                    = "ami-06b21ccaeff8cd686" # Amazon Linux 2023
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y docker
                systemctl start docker
                systemctl enable docker
                usermod -aG docker ec2-user

                # Iniciar Jenkins sin Setup Wizard
                docker run -d -p 8080:8080 -p 50000:50000 \
                --name jenkins \
                -u root \
                -v jenkins_home:/var/jenkins_home \
                -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
                jenkins/jenkins:lts

                # Esperar a que Jenkins arranque
                sleep 30

                # Crear usuario administrador
                docker exec jenkins bash -c 'echo "jenkins.model.Jenkins.instance.securityRealm.createAccount(\"admin\", \"admin123\")" | java -jar /var/jenkins_home/war/WEB-INF/jenkins-cli.jar -s http://localhost:8080/ groovy ='
                EOF


  tags = { Name = "jenkins_server" }
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}
