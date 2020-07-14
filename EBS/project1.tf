// Logging in AWS account

provider "aws" {
	region = "ap-south-1"
	profile = "myprofile"
}

// Creating key pair

resource "tls_private_key" "mykey" {
	algorithm = "RSA"
}

resource "aws_key_pair" "generated_key" {
	key_name   = "project_key1122"
	public_key = tls_private_key.mykey.public_key_openssh

	depends_on = [
		tls_private_key.mykey
	]
}

resource "local_file" "key-file" {
	content = tls_private_key.mykey.private_key_pem
	filename = "mykey.pem"
}

// Creating Security Group 

resource "aws_security_group" "allow_http" {
	name        = "webserver_sg"
 	description = "Allow HTTP inbound traffic"
	
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
    		Name = "allow_webhosting"
  	}
}

// Launching EC2 instance with above Key Pair and Security Group

resource "aws_instance" "web" {
  	ami           = "ami-0447a12f28fddb066"
  	instance_type = "t2.micro"
	key_name      = aws_key_pair.generated_key.key_name
	security_groups = [aws_security_group.allow_http.name]

	connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = file("C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/project1/${local_file.key-file.filename}")
    		host     = aws_instance.web.public_ip
  	}

	provisioner "remote-exec" {
    		inline = [
      			"sudo yum install git httpd php -y",
      			"sudo systemctl restart httpd",
			"sudo systemctl enable httpd"
    		]
  	}

  	tags = {
    		Name = "MyOS1"
  	}
}

// Creating 1 GiB EBS Volume 

resource "aws_ebs_volume" "esb1" {
	availability_zone = aws_instance.web.availability_zone
	size              = 1

	tags = {
		Name = "Myebs1"
	}
}

// Attaching the EBS Volume with the instance

resource "aws_volume_attachment" "ebs_att" {
	device_name  = "/dev/sdh"
	volume_id    = aws_ebs_volume.esb1.id
	instance_id  = aws_instance.web.id
	force_detach = true
}

resource "null_resource" "nullremote1" {
	depends_on = [
		aws_volume_attachment.ebs_att
	]

	connection {
		type = "ssh"
		user= "ec2-user"
		private_key = file("C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/project1/${local_file.key-file.filename}")
		host = aws_instance.web.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo mkfs.ext4 /dev/xvdh",
			"sudo mount /dev/xvdh /var/www/html",
			"sudo rm -rf /var/www/html/*",
			"sudo git clone https://github.com/saurabhagarwal43800/Terraform.git /var/www/html"
		]
	}
}

// Creating S3 bucket

resource "aws_s3_bucket" "mybucket" {
  	bucket = "project1-bucket1122"
  	acl    = "public-read"
	region = "ap-south-1"

  	tags = {
    		Name        = "My bucket"
    		Environment = "Dev"
  	}
	
	provisioner "local-exec" {
		command = "git clone https://github.com/saurabhagarwal43800/Terraform.git C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/project1/repo/"
	}
	provisioner "local-exec" {
		when = destroy
		command = "rm -rf C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/project1/repo"
  	}
}

resource "aws_s3_bucket_object" "object" {
	depends_on   = [
		aws_s3_bucket.mybucket
	]
  	
	bucket 	     = aws_s3_bucket.mybucket.bucket
  	key    	     = "terraform.png"
	source	     = "C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/project1/repo/imgs/terraform.png"
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
    aws_instance.web
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
    		private_key = file("C:/Users/500060783/Desktop/Hybrid_Cloud/terraform/project1/${local_file.key-file.filename}")
    		host     = aws_instance.web.public_ip
  	}
	provisioner "remote-exec" {
    		inline = [
      			"sudo su << EOF",
      			"echo \"<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key }'>\" >> /var/www/html/index.php",
       "EOF"
		]
	}
  	provisioner "local-exec" {
		command = "chrome ${aws_instance.web.public_ip}"
  	}
}

resource "aws_ebs_snapshot" "ebs_snapshot" {
	depends_on = [
		null_resource.nullmix
	]
  	volume_id = aws_ebs_volume.esb1.id

  	tags = {
    		Name = "Webserver_snap"
  	}
}