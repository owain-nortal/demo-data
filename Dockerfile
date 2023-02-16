FROM python:3.10.10-buster
WORKDIR /usr/src/app
RUN apt update 
RUN apt-get install -y ruby jq
RUN python --version
RUN pip3 install --upgrade neosctl 
RUN neosctl --version
RUN rm -rf /var/lib/apt/lists/*
COPY . .
ENTRYPOINT ["./entrypoint.sh"]