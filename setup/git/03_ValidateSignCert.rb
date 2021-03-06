test_name "Validate Sign Cert"

step "Master: Start Puppet Master"
with_master_running_on(master, "--certdnsnames=\"puppet:$(hostname -s):$(hostname -f)\" --verbose") do
  step "Agents: Run agent --test first time to gen CSR "
  on agents, puppet_agent("--test"), :acceptable_exit_codes => [1]

  # Sign all waiting certs
  step "Master: sign all certs"
  on master, puppet_cert("--sign --all")
end
