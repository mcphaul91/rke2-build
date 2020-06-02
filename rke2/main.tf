terraform {
  backend "local" {
    path = "server.tfstate"
  }
}

locals {
  name                      = var.name
  rke2_cluster_secret       = var.rke2_cluster_secret
  rke2_version              = var.rke2_version
}

provider "aws" {
  region  = "us-east-2"
  profile = "rancher-eng"
}

resource "aws_security_group" "rke2-server" {
  name   = "${local.name}-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
    from_port   = 9345
    to_port     = 9345
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
  
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 9099
    to_port     = 9099
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rke2-agent" {
  name   = "${local.name}-pool"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 9099
    to_port     = 9099
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "rke2-master-nlb" {
  name               = "${local.name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets = data.aws_subnet_ids.available.ids
}

resource "aws_route53_record" "www" {
   # currently there is the only way to use nlb dns name in rke2
   # because the real dns name is too long and cause an issue
   zone_id = "${var.zone_id}"
   name = "${var.domain_name}"
   type = "CNAME"
   ttl = "30"
   records = ["${aws_lb.rke2-master-nlb.dns_name}"]
}


resource "aws_lb_target_group" "rke2-master-nlb-tg" {
  name     = "${local.name}-nlb-tg"
  port     = "6443"
  protocol = "TCP"
  vpc_id   = data.aws_vpc.default.id
  deregistration_delay = "300"
  health_check {
    interval = "30"
    port = "6443"
    protocol = "TCP"
    healthy_threshold = "10"
    unhealthy_threshold= "10"
  }
}

resource "aws_lb_listener" "rke2-master-nlb-tg" {
  load_balancer_arn = "${aws_lb.rke2-master-nlb.arn}"
  port              = "6443"
  protocol          = "TCP"
  default_action {
    target_group_arn = "${aws_lb_target_group.rke2-master-nlb-tg.arn}"
    type             = "forward"
  }
}

resource "aws_lb_target_group" "rke2-master-supervisor-nlb-tg" {
  name     = "${local.name}-nlb-supervisor-tg"
  port     = "9345"
  protocol = "TCP"
  vpc_id   = data.aws_vpc.default.id
  deregistration_delay = "300"
  health_check {
    interval = "30"
    port = "9345"
    protocol = "TCP"
    healthy_threshold = "10"
    unhealthy_threshold= "10"
  }
}

resource "aws_lb_listener" "rke2-master-supervisor-nlb-tg" {
  load_balancer_arn = "${aws_lb.rke2-master-nlb.arn}"
  port              = "9345"
  protocol          = "TCP"
  default_action {
    target_group_arn = "${aws_lb_target_group.rke2-master-supervisor-nlb-tg.arn}"
    type             = "forward"
  }
}

resource "aws_lb_target_group_attachment" "rke2-nlb-attachement" {
  count = "${var.server_count}"
  target_group_arn = "${aws_lb_target_group.rke2-master-nlb-tg.arn}"
  target_id        = "${aws_instance.rke2-server[count.index].id}"
  port             = 6443
}

resource "aws_lb_target_group_attachment" "rke2-nlb-supervisor-attachement" {
  count = "${var.server_count}"
  target_group_arn = "${aws_lb_target_group.rke2-master-supervisor-nlb-tg.arn}"
  target_id        = "${aws_instance.rke2-server[count.index].id}"
  port             = 9345
}

resource "aws_eip" "rke2-server-eip" {
  count            = "${var.server_count}"
  vpc              = true
}

resource "aws_instance" "rke2-server" {
  count = "${var.server_count}"
  instance_type = var.server_instance_type
  ami           = data.aws_ami.ubuntu.id
  user_data     = base64encode(templatefile("${path.module}/files/server_userdata.tmpl",
  {
    extra_ssh_keys = var.extra_ssh_keys,
    rke2_cluster_secret = local.rke2_cluster_secret,
    rke2_version = local.rke2_version,
    rke2_server_args = var.rke2_server_args,
    lb_address = aws_eip.rke2-server-eip[0].public_ip,
    domain_name = var.domain_name
    master_index = count.index,
    rke2_arch = var.rke2_arch,
    debug = var.debug,}))
  security_groups = [
    aws_security_group.rke2-server.name,
  ]

   root_block_device {
    volume_size = "30"
    volume_type = "gp2"
  }
   tags = {
    Name = "${local.name}-server-${count.index}"
    Role = "master"
    Leader = "${count.index == 0 ? "true" : "false"}"
  }
  provisioner "local-exec" {
      command = "sleep 10"
  }
}

resource "aws_eip_association" "eip_assoc" {
  count = "${var.server_count}"
  instance_id   = "${aws_instance.rke2-server[count.index].id}"
  allocation_id = "${aws_eip.rke2-server-eip[count.index].id}"
}

module "rke2-pool-agent-asg" {
  source        = "terraform-aws-modules/autoscaling/aws"
  version       = "3.0.0"
  name          = "${local.name}-pool"
  asg_name      = "${local.name}-pool"
  instance_type = var.agent_instance_type
  image_id      = data.aws_ami.ubuntu.id
  user_data     = base64encode(templatefile("${path.module}/files/agent_userdata.tmpl",
  {
    rke2_url = aws_eip.rke2-server-eip[0].public_ip,
    extra_ssh_keys = var.extra_ssh_keys,
    rke2_cluster_secret = local.rke2_cluster_secret,
    rke2_version = local.rke2_version,
    rke2_agent_args = var.rke2_agent_args,
    lb_address = var.domain_name,
    rke2_arch = var.rke2_arch
    debug = var.debug,}))
 
  ebs_optimized = true

  default_cooldown          = 10
  health_check_grace_period = 30
  wait_for_capacity_timeout = "60m"

  desired_capacity    = var.agent_node_count
  health_check_type   = "EC2"
  max_size            = var.agent_node_count
  min_size            = var.agent_node_count
  vpc_zone_identifier = [data.aws_subnet.selected.id]
  spot_price          = "0.680"

  security_groups = [
    aws_security_group.rke2-agent.id,
  ]
  lc_name = "${local.name}-pool"

  root_block_device = [
    {
      volume_size = "30"
      volume_type = "gp2"
    },
  ]
}

resource "null_resource" "get-kubeconfig" {
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "until ssh -i ${var.ssh_key_path} ubuntu@${aws_eip.rke2-server-eip[0].public_ip} 'sudo sed \"s/localhost/$var.domain_name}/g;s/127.0.0.1/${var.domain_name}/g\" /etc/rancher/rke2/rke2.yaml' >| ./kubeconfig.yaml; do sleep 5; done"
  }
}

