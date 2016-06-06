#!/usr/bin/env ruby

# Read config in format NAME="value" or NAME=value (default for OpenVZ)
def read_ovz_config(filename)
    config = Hash.new
    config_file = File.new(filename)
    while line = config_file.gets
        if line =~ /^\s*(\w+)\s*=\s*"?([^"\n ]+)"?/
            config[$1] = $2
        end
    end
    config_file.close
    return config
end

def create_symlink(src, dest)
    OpenNebula.exec_and_log("#{$sudo} ln -sf \"#{src}\" \"#{dest}\"")
end

# Read exports from shell script
def read_shell_exports(filename)
    file = File.new(filename)
    while line = file.gets
        if line =~ /^\s*export\s+(\w+)=(.*)/
            # TODO: check if there's already such variable defined
            ENV[$1] = $2
        end
    end
end

def normalize_path(path)
    path.gsub!(/\/\/+/, "/")
end

def guess_tarball_type(filename)
    out = `file "#{filename}"`
    return :gzip if $?.exitstatus != 0

    if out =~ /gzip compressed data/
        return :gzip
    elsif out =~ /bzip2 compressed data/
        return :bzip2
    elsif out =~ /xz compressed data/
        return :xz
    end

    return :gzip
end

def guess_container_type(filename, compress)
    tarball_contents = `tar -tf \"#{filename}\" --#{compress.to_s} --exclude=\"*/*/*\"`
    if (tarball_contents =~ /\.\/var/ and
        tarball_contents =~ /\.\/bin/ and
        tarball_contents =~ /\.\/etc/ and
        tarball_contents =~ /\.\/usr/)
        # looks like we have a unix system inside
        :simfs
    else
        # otherwise it should be ploop
        :ploop
    end
end

def make_vm_conf(doc, vm_conf, deployment_dirname)
    doc.elements.each('VM/TEMPLATE/NIC/IP') do |ip|
	vm_conf["IP_ADDRESS"] = ip.text
    end

    doc.elements.each('VM/TEMPLATE/MEMORY') do |mem|
	vm_conf["PHYSPAGES"] = "0:#{mem.text}M"
    end

    vm_conf["SWAPPAGES"] = "0:128M"
    doc.elements.each('VM/TEMPLATE/DISK[translate(TYPE,"SWAP","swap") = "swap"]/SIZE') do |swap|
	vm_conf["SWAPPAGES"] = "0:#{swap.text}M"
    end

    doc.elements.each('VM/TEMPLATE/DISK[translate(TYPE,"SWAP","swap") != "swap"]/SIZE') do |disk_size|
	soft_limit = disk_size.text.to_i
	hard_limit = soft_limit * 1.1
	hard_limit = hard_limit.round
	if hard_limit > 1024 then
	  vm_conf["DISKSPACE"] = "#{soft_limit}M:#{hard_limit}M"
	end
    end


    doc.elements.each('VM/TEMPLATE/DISK[translate(TYPE,"SWAP","swap") != "swap"]/OVZ_SIZE') do |disk_size|
	soft_limit = disk_size.text.to_i
	hard_limit = soft_limit * 1.1
	hard_limit = hard_limit.round
	if hard_limit > 1024 then
	  vm_conf["DISKSPACE"] = "#{soft_limit}M:#{hard_limit}M"
	end
    end

    vm_conf["VE_ROOT"] = File.join(deployment_dirname, "root")
    normalize_path(vm_conf["VE_ROOT"])
    vm_conf["VE_PRIVATE"] = File.join(deployment_dirname, "private")
    normalize_path(vm_conf["VE_PRIVATE"])

    vm_conf["OSTEMPLATE"] = "default"
    doc.elements.each('VM/USER_TEMPLATE/OSTEMPLATE') do |ost|
	vm_conf["OSTEMPLATE"] = ost.text
    end

    # Extract network-related values from context
    doc.elements.each('VM/TEMPLATE/CONTEXT/ETH0_DNS') do |nameserver|
	vm_conf["NAMESERVER"] = nameserver.text
    end

    doc.elements.each('VM/TEMPLATE/CONTEXT/HOSTNAME') do |hostname|
	vm_conf["HOSTNAME"] = hostname.text
    end

    doc.elements.each('VM/TEMPLATE/CONTEXT/SEARCHDOMAIN') do |sdomain|
	vm_conf["SEARCHDOMAIN"] = sdomain.text
    end

    doc.elements.each('VM/TEMPLATE/RAW/*') do |raw|
	vm_conf[raw.name] = raw.text
    end

    lookup = false
    doc.elements.each('VM/USER_TEMPLATE/LOOKUP_HOSTNAME') do |lkp|
	if lkp.text == "true" then lookup = true end
    end

    doc.elements.each('VM/TEMPLATE/CPU') do |cpu|
	vm_conf["CPULIMIT"] = cpu.text.to_i * 100
    end

    doc.elements.each('VM/TEMPLATE/VCPU') do |vcpu|
	vm_conf["CPUS"] = vcpu.text
    end

    # Resolve hostname from DNS if required
    if lookup
      OpenNebula.log_info("lookup hostname is true")
      if vm_conf["HOSTNAME"] != nil
	OpenNebula.log_info("DNS hostname resolver: not overriding context-specified hostname #{vm_conf["HOSTNAME"]}.")
      elsif vm_conf["IP_ADDRESS"] == nil
	OpenNebula.error_message("DNS hostname resolver: no IP address specified!")
      else
	hostname = `#{$host} #{vm_conf["IP_ADDRESS"]}`
	if hostname =~ /.*not found.*/
	  OpenNebula.log_error("DNS hostname resolver: couldn't resolve name for IP #{vm_conf["IP_ADDRESS"]}.  Not setting hostname.")
	else
	  hostname = hostname.split.last
	  if hostname[-1..-1] == "." then hostname = hostname[0..-2] end
	  OpenNebula.log_info("DNS hostname resolver: setting hostname to #{hostname}")
	  vm_conf["HOSTNAME"] = hostname
	end
      end
    end
    
    return vm_conf
end
