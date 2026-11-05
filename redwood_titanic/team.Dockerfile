# Image for team_server=true (D23): the pilot image plus OpenSSH. The four agent containers use it
# for the ssh client; the fifth service, `team`, runs sshd from it. Nothing else changes.
FROM redwood-titanic-env:pilot
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client openssh-server \
    && apt-get clean && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd
