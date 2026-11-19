# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t compound_stack_rails .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name compound_stack_rails compound_stack_rails

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.10
# The published image the patched Ruby is compiled over (see the block below FROM).
ARG RUBY_BASE_VERSION=4.0.7
FROM docker.io/library/ruby:$RUBY_BASE_VERSION-slim AS base
# Ruby 4.0.10 is compiled from its release tarball over the ruby:$RUBY_BASE_VERSION-slim
# image, because docker.io/library/ruby:4.0.10-slim is not published yet. It fixes the
# Regexp and String vulnerabilities of 2026-11-18 (https://www.ruby-lang.org/en/news/2026/11/18/multiple-vulnerabilities-in-regexp-and-string/).
# When that image is out: delete this block and RUBY_BASE_VERSION, and build FROM
# ruby:$RUBY_VERSION-slim again. RUBY_SOURCE_VERSION has its own name because the
# base image sets ENV RUBY_VERSION, and an ENV beats an ARG of the same name.
ARG RUBY_SOURCE_VERSION=4.0.10
ARG RUBY_SOURCE_SHA256=1537f7a6003c436546ecab6b48b6e7725a9af2328f45a8af7f42f41c5df90ab8
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update -qq; \
    apt-get install --no-install-recommends -y ca-certificates dpkg-dev g++ gcc make rustc wget xz-utils \
      libffi-dev libgmp-dev libssl-dev libyaml-dev zlib1g-dev; \
    wget -qO /tmp/ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_SOURCE_VERSION%.*}/ruby-${RUBY_SOURCE_VERSION}.tar.xz"; \
    echo "${RUBY_SOURCE_SHA256} */tmp/ruby.tar.xz" | sha256sum --check --strict; \
    mkdir -p /usr/src/ruby; \
    tar -xJf /tmp/ruby.tar.xz -C /usr/src/ruby --strip-components=1; \
    rm /tmp/ruby.tar.xz; \
    cd /usr/src/ruby; \
    ./configure --build="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" --disable-install-doc --enable-shared --enable-yjit; \
    make -j"$(nproc)"; \
    make install DESTDIR=/tmp/ruby-install; \
    rm -rf /usr/local/lib/ruby /usr/local/lib/libruby* /usr/local/include/ruby-*; \
    cp -a /tmp/ruby-install/usr/local/. /usr/local/; \
    rm -rf /tmp/ruby-install; \
    cd /; \
    rm -rf /usr/src/ruby; \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
    find /usr/local -type f -executable -not -path '/usr/local/bundle/*' -exec ldd '{}' ';' 2>/dev/null \
      | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
      | sort -u | xargs -r dpkg-query --search | cut -d: -f1 | sort -u | xargs -r apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb; \
    ruby -e 'abort "built #{RUBY_VERSION}, wanted #{ARGV[0]}" unless RUBY_VERSION == ARGV[0]' "$RUBY_SOURCE_VERSION"; \
    ruby --yjit -e 'abort "no YJIT" unless RubyVM::YJIT.enabled?'; \
    gem --version; bundle --version
ENV RUBY_VERSION=$RUBY_SOURCE_VERSION \
    RUBY_DOWNLOAD_URL=https://cache.ruby-lang.org/pub/ruby/4.0/ruby-$RUBY_SOURCE_VERSION.tar.xz \
    RUBY_DOWNLOAD_SHA256=$RUBY_SOURCE_SHA256


# Rails app lives here
WORKDIR /rails

# Install base packages. librsvg2-2 + fontconfig render the profile share cards
# (ProfileCard); the fonts themselves are vendored in vendor/fonts. libstdc++6 is
# what the Node binary copied into the final image links against.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl fontconfig libjemalloc2 libstdc++6 librsvg2-2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems and node modules
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips libyaml-dev node-gyp pkg-config python-is-python3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install Node.js for the Vite production build. Only the node binary reaches the
# final image, to run the SSR render server.
ARG NODE_VERSION=24.21.0
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    rm -rf /tmp/node-build-master

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock .ruby-version ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Install node modules (dev deps included — Vite itself is a devDependency)
COPY package.json package-lock.json ./
RUN npm ci

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY. This
# builds the client bundle (public/vite) and the self-contained SSR bundle
# (public/vite-ssr/ssr.js), then drops node_modules — neither needs it at runtime.
# Precompiling boots the app, which leaves an empty storage/production.sqlite3.
# Docker copies an image's files into a new named volume on first mount, so a
# fresh deploy would start with that file and db:prepare would skip loading the
# queue, cache, and cable schemas.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules && \
    rm -f storage/*.sqlite3*




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Node runs the SSR render server (bin/ssr, started beside Rails by bin/docker-entrypoint).
COPY --from=build /usr/local/node/bin/node /usr/local/bin/node

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
