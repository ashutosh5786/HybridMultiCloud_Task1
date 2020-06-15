provider "aws" {
  region = "ap-south-1"
}

//Creating The Key and Saving them on The Disk

resource "tls_private_key" "mykey"{
	algorithm = "RSA"
}

resource "aws_key_pair" "key1" {
  key_name   = "key3"
  public_key = tls_private_key.mykey.public_key_openssh
}
 
resource "local_file" "key_pair_save"{
   content = tls_private_key.mykey.private_key_pem
   filename = "key.pem"
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//Creating The Security Group And Allowing The HTTP and SSH
resource "aws_security_group" "sec-grp" {

    depends_on = [
        tls_private_key.mykey,
        local_file.key_pair_save,
        aws_key_pair.key1
    ]
  name        = "Allowing SSH and HTTP"
  description = "Allow ssh & http connections"
 
  ingress {
    description = "Allowing Connection for SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allowing Connection For HTTP"
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
    Name = "Web-Server"
  }
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// Launching The Volume
resource "aws_ebs_volume" "my_vol" {
    depends_on = [
        aws_instance.web1
    ]
  availability_zone = aws_instance.web1.availability_zone
  size              = 1

  tags = {
    Name = "P.D"
  }
}
// Attaching The Volume to The Instance

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.my_vol.id
  instance_id = aws_instance.web1.id
  force_detach = true
}


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//Launching The Instances
    resource "aws_instance" "web1" {

        depends_on = [
            tls_private_key.mykey,
            aws_key_pair.key1,
            local_file.key_pair_save,
            aws_security_group.sec-grp,
        ]
        ami = "ami-0447a12f28fddb066"
        instance_type = "t2.micro"
        key_name = "key3"
        security_groups = ["${aws_security_group.sec-grp.name}"]
        tags = {
        Name = "Web-Server"
                }

        connection {
            type = "ssh"
            user = "ec2-user"
            private_key = tls_private_key.mykey.private_key_pem
            host = aws_instance.web1.public_ip
        }

        provisioner "remote-exec" {
            inline = [
                "sudo yum install httpd  php git -y",
                "sudo systemctl restart httpd",
                "sudo systemctl enable httpd",
            ]
        
        }
    }

    resource "null_resource" "null1" {
        depends_on = [
            aws_volume_attachment.ebs_att
        ]
            connection {
            type = "ssh"
            user = "ec2-user"
            private_key = tls_private_key.mykey.private_key_pem
            host = aws_instance.web1.public_ip
        }

        provisioner "remote-exec" {
            inline = [
                "sudo mkfs.ext4 /dev/xvdh",
                "sudo mount /dev/xvdh /var/www/html",
                "sudo rm -rf /var/www/html/*",
                "sudo git clone https://github.com/ashutosh5786/for-ec2.git /var/www/html"
                ]
        
        }
    }

    resource "null_resource" "null2" {
        depends_on = [
            null_resource.null5
        ]

        provisioner "local-exec" {
            command = "chrome ${aws_instance.web1.public_ip}"
        
        }
    }

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//Creating the S3 Bucket
resource "aws_s3_bucket" "b2" {
    bucket = "web-s3"
    acl    = "public-read"
    versioning {
      enabled = true
    }

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Uplaoding File to Bucket
resource "aws_s3_bucket_object" "object" {
    depends_on = [
        null_resource.null3,
        aws_s3_bucket.b2
    ]
  bucket = aws_s3_bucket.b2.bucket
  key    = "img.png"
  source = "./image/12.png"
  acl = "public-read"
  }


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Downlaod img The Images from The Github on local dir
resource "null_resource" "null3"{
  
    provisioner "local-exec" {
      command = "git clone https://github.com/ashutosh5786/for-ec2.git ./image"
    }

}
// Delting the Image from local Directory
resource "null_resource" "null4"{
    depends_on = [
      aws_s3_bucket_object.object
    ]
    provisioner "local-exec" {
        
      command = "RMDIR /Q/S image"
    }

}


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//Creating CloudFront And Attaching it to S3
resource "aws_cloudfront_distribution" "distribution" {
   depends_on = [aws_s3_bucket.b2,
                null_resource.null1
  ]
    origin {
        domain_name = "web-s3.s3.amazonaws.com"
        origin_id = aws_s3_bucket.b2.id

        custom_origin_config {
            http_port = 80
            https_port = 80
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
    }

    enabled = true

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = aws_s3_bucket.b2.id


        forwarded_values {
            query_string = false


            cookies {
               forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }


    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }


    viewer_certificate {
        cloudfront_default_certificate = true
    }
}


 
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Updating The URL in HTML file 


    resource "null_resource" "null5" {
        depends_on = [
            aws_cloudfront_distribution.distribution
        ]
            connection {
            type = "ssh"
            user = "ec2-user"
            private_key = tls_private_key.mykey.private_key_pem
            host = aws_instance.web1.public_ip
        }

        provisioner "remote-exec" {
            inline = [
                "cd /var/www/html",
                "sudo sed -i 's/12.png/https:${aws_cloudfront_distribution.distribution.domain_name}\\/img.png/g' index.html"
                ]
        
        }
    }



