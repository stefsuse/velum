FROM opensuse/leap:42.3 as intermediate
#### BUILD AND DEPLOYMENT STEPS ####

# Install stuff taken for granted on IBS images
RUN zypper in -y ruby-devel tar wget

ENV BUNDLER_BIN=/srv/velum/vendor/bundle/ruby/2.1.0/bin/bundler.ruby2.1
ENV GEM_PATH=/srv/velum/vendor/bundle/ruby/2.1.0
ENV IGNORE_ASSETS=yes
ENV RAILS_ENV=production
ENV RAILS_USE_STATIC_FILES=true
#TODO why wildcard here? blindly pasting from existing image
ENV RUBYLIB=/srv/velum/vendor/bundle/ruby/2.1.0/gems/bundler*/lib

# put source - wildcard not supported
COPY app/ /srv/velum/app
COPY bin/ /srv/velum/bin
COPY config/ /srv/velum/config
COPY lib/ /srv/velum/lib
COPY public/ /srv/velum/public
COPY spec/ /srv/velum/spec

# individual required files
COPY Gemfile /srv/velum
COPY Gemfile.lock /srv/velum
COPY config.ru /srv/velum
COPY LICENSE /srv/velum
COPY Rakefile /srv/velum
COPY VERSION /srv/velum

# other steps derived from setup scripts and mystery files on IBS
RUN cd /srv/velum &&\
    mkdir -p /var/lib/velum &&\ 
    mkdir -p /srv/velum/{log,tmp,vendor} &&\ 
    mkdir -p /srv/velum/vendor/bundle 

RUN ln -s /srv/velum/vendor/bundle/ruby/2.1.0/bin/bundler.ruby2.1 /bin/bundle

RUN gem install --no-ri --no-rdoc bundler --version '<= 1.17.3' -n /bin

RUN find /{bin,usr} -type f -name "bundle*" -exec /bin/ls -l {} \;

RUN bundle.ruby2.1 env
    
RUN ls -lrt /var/lib/velum &&\
    cp /srv/velum/Gemfile.lock /var/lib/velum/

RUN bundle.ruby2.1 config --local frozen 0 &&\
    bundle.ruby2.1 config --local build.nokogiri --use-system-libraries &&\ 
    echo $PATH &&\
    echo $(pwd)

RUN bundle.ruby2.1 install --deployment --binstubs=/usr/local/bin --path=/var/lib/velum

RUN wget -q https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-2.1.1-linux-x86_64.tar.bz2 -P /opt &&\ 
    tar -xjf /opt/phantomjs-2.1.1-linux-x86_64.tar.bz2 -C /opt &&\ 
    mv /opt/phantomjs-2.1.1-linux-x86_64/bin/phantomjs /usr/local/bin &&\ 
    rm -rf /opt/phantomjs-2.1.1-linux-x86_64

#### APPLICATION CONFIG ONLY ####
# Trying to create a smaller image - not fully tested yet 
FROM opensuse/leap:42.3

ENV BUNDLE_DISABLE_SHARED_GEMS=1 
ENV BUNDLE_FROZEN=1 
ENV BUNDLE_GEMFILE=/srv/velum/Gemfile
ENV BUNDLE_PATH=/srv/velum 

COPY --from=intermediate /var/lib/velum /srv/velum

WORKDIR /srv/velum
EXPOSE 80

CMD [entrypoint.sh]
