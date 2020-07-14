provider "aws" {
	region  = "ap-south-1"
	profile = "myprofile"
}

// Key Pair
resource "tls_private_key" "mykey" {
	algorithm = "RSA"
}

resource "aws_key_pair" "generated_key" {
	key_name   = "project2_key"
	public_key = tls_private_key.mykey.public_key_openssh

	depends_on = [
		tls_private_key.mykey
	]
}

resource "local_file" "key-file" {
	content = tls_private_key.mykey.private_key_pem
	filename = "project2_key.pem"
}

// Creating S.G. for allowing ssh, nfs, httpd
resource "aws_security_group" "allow_nfs" {
	depends_on = [
		aws_vpc.my_vpc
	]
  	name        = "allow_nfs_http_ssh"
  	description = "Allow NFS, HTTP & SSH inbound traffic"
	vpc_id = "${aws_vpc.my_vpc.id}"
  	ingress {
    		description = "NFS from VPC"
    		from_port   = 2049
    		to_port     = 2049
    		protocol    = "tcp"
    		cidr_blocks = ["0.0.0.0/0"]
  	}

  	ingress {
		description = "SSH"
    		from_port   = 22
    		to_port     = 22
    		protocol    = "tcp"
    		cidr_blocks = ["0.0.0.0/0"]
  	}
  	ingress {
		description = "HTTP"
    		from_port   = 80
    		to_port     = 80
    		protocol    = "tcp"
    		cidr_blocks = ["0.0.0.0/0"]
  	}

  	egress {
    	from_port   = 0
    	to_port     = 0
    	protocol    = "-1"
    	cidr_blocks = ["0.0.0.0/0"]
  	}

  	tags = {
    		Name = "allow_nfs"
  	}
}
// Creating VPC
resource "aws_vpc" "my_vpc" {
	enable_dns_hostnames = true
  	cidr_block = "10.0.0.0/16"
	tags = {
		Name = "MyVPC"
	}
}

// Creating subnet in the vpc
resource "aws_subnet" "alpha" {
  	vpc_id            = "${aws_vpc.my_vpc.id}"
  	availability_zone = "ap-south-1a"
  	cidr_block        = "10.0.1.0/24"
	map_public_ip_on_launch = true
	tags = {
		Name = "Subnet-1a"
	}
}

// Creating Internet Gateway for VPC
resource "aws_internet_gateway" "gw" {
  	vpc_id = "${aws_vpc.my_vpc.id}"
  	tags = {
    		Name = "myIGW"
  	}
}

// Creating a route table for VPC
resource "aws_route_table" "rt" {
  	vpc_id = "${aws_vpc.my_vpc.id}"

  	route {
    		cidr_block = "0.0.0.0/0"
    		gateway_id = "${aws_internet_gateway.gw.id}"
  	}
	tags = {
    		Name = "my_RT"
  	}
}

// Associating Route Table
resource "aws_route_table_association" "rt_ass" {
  	subnet_id      = "${aws_subnet.alpha.id}"
  	route_table_id = "${aws_route_table.rt.id}"
}

// Creating efs file system
resource "aws_efs_file_system" "efs" {
	tags = {
    		Name = "MyEFS"
  	}
}

// Creating mount target for efs file system
resource "aws_efs_mount_target" "efs_mount" {
  	file_system_id = "${aws_efs_file_system.efs.id}"
  	subnet_id      = "${aws_subnet.alpha.id}"
	security_groups= ["${aws_security_group.allow_nfs.id}"]
}

// Creating EC2 instance
resource "aws_instance" "efs_os" {
	depends_on = [
		aws_efs_mount_target.efs_mount
	]
  	ami             = "ami-0732b62d310b80e97"
  	instance_type   = "t2.micro"
	availability_zone = "ap-south-1a"
	key_name        = "${aws_key_pair.generated_key.key_name}"
	security_groups = ["${aws_security_group.allow_nfs.id}"]
  	subnet_id	= "${aws_subnet.alpha.id}"
	tags = {
    		Name = "EFS_OS"
  	}
}

resource "null_resource" "nullremote1" {
	depends_on = [
		aws_instance.efs_os
	]
	connection {
		type = "ssh"
		user= "ec2-user"
		private_key = file("C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/efs/${local_file.key-file.filename}")
		host = aws_instance.efs_os.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo yum install -y httpd php git amazon-efs-utils nfs-utils",
			"sudo setenforce 0",
			"sudo systemctl start httpd",
			"sudo systemctl enable httpd",
			"sudo mount -t efs ${aws_efs_file_system.efs.id}:/ /var/www/html",
			"sudo echo '${aws_efs_file_system.efs.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
			"sudo rm -rf /var/www/html/*",
			"sudo git clone https://github.com/saurabhagarwal43800/Deploy-Webserver-with-CloudFront-using-Terraform.git /var/www/html/"
		]
	}
}

// Creating S3 bucket
resource "aws_s3_bucket" "mybucket" {
  	bucket = "project2-bucket1122"
  	acl    = "public-read"
	region = "ap-south-1"

  	tags = {
    		Name        = "My bucket"
    		Environment = "Dev"
  	}
	
	provisioner "local-exec" {
		command = "git clone https://github.com/saurabhagarwal43800/Deploy-Webserver-with-CloudFront-using-Terraform.git C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/efs/repo/"
	}
	provisioner "local-exec" {
		when = destroy
		command = "rm -rf C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/efs/repo"
  	}
}

resource "aws_s3_bucket_object" "object" {
	depends_on   = [
		aws_s3_bucket.mybucket
	]
  	
	bucket 	     = aws_s3_bucket.mybucket.bucket
  	key    	     = "terraform.png"
	source	     = "C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/efs/repo/imgs/terraform.png"
	content_type = "image/png"
  	acl	     = "public-read"
}

locals {
  	s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  	comment = "CloudFront S3 sync"
}

// Creating CloudFront Distribution for S3

resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [
    aws_key_pair.generated_key,
    aws_instance.efs_os
  ]	
  origin {
    domain_name = aws_s3_bucket.mybucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "ClouFront S3 sync"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

}
resource "null_resource" "nullmix" {
	depends_on = [
		aws_cloudfront_distribution.s3_distribution
	]
	connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = file("C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/efs/${local_file.key-file.filename}")
    		host     = aws_instance.efs_os.public_ip
  	}
	provisioner "remote-exec" {
    		inline = [
      			"sudo su << EOF",
      			"echo \"<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key }'>\" >> /var/www/html/index.php",
       "EOF"
		]
	}
  	provisioner "local-exec" {
		command = "chrome ${aws_instance.efs_os.public_ip}"
  	}
}