FROM public.ecr.aws/docker/library/ubuntu:24.04@sha256:e3f92abc0967a6c19d0dfa2d55838833e947b9d74edbcb0113e48535ad4be12a
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get clean 
RUN apt-get install postgresql-client-16 -y 
RUN apt-get install pip curl jq unzip -y --no-install-recommends
RUN apt-get install mariadb-client -y --no-install-recommends
RUN mkdir -p /tmp/cold_tmpdir
WORKDIR "/tmp/cold_tmpdir/"
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN ./aws/install

RUN apt-get -y install git binutils rustc cargo pkg-config libssl-dev --no-install-recommends
RUN git clone https://github.com/aws/efs-utils
WORKDIR "/tmp/cold_tmpdir/efs-utils/"
RUN ./build-deb.sh && apt-get -y install ./build/amazon-efs-utils*deb
RUN rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
CMD ["entrypoint.sh"]
