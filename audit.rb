#!/usr/bin/ruby -w
# -*- coding: utf-8 -*-

require 'optparse'
require 'json'

options = {
  racine: '/',
  json: false,
  top_n: 5,
  services: ['ssh', 'cron', 'docker']
}

OptionParser.new do |opts|
  opts.on("-r", "--racine RACINE", "Répertoire racine (défaut: /)") { |r| options[:racine] = r }
  opts.on("-j", "--json", "Format de sortie en JSON") { options[:json] = true }
  opts.on("-n", "--top N", Integer, "Nombre de processus à afficher") { |n| options[:top_n] = n }
  opts.on("-s", "--services S1,S2", Array, "Services à vérifier") { |s| options[:services] = s }
end.parse!

resultats = {}

hostname = `hostname`.strip
resultats[:hostname] = ($?.exitstatus == 0) ? hostname : "Erreur"

noyau = `uname -r`.strip
resultats[:noyau] = ($?.exitstatus == 0) ? noyau : "Erreur"

begin
  os_release = File.read("#{options[:racine]}etc/os-release")
  if m = os_release.match(/PRETTY_NAME="(.*?)"/)
    resultats[:distribution] = m[1]
  end
rescue Errno::ENOENT => e
  resultats[:distribution] = "Fichier introuvable"
rescue Exception => e
  resultats[:distribution] = "Erreur: #{e}"
end

begin
  uptime_data = File.read("#{options[:racine]}proc/uptime").split[0].to_f
  resultats[:uptime_secondes] = uptime_data
rescue Exception => e
  resultats[:uptime_secondes] = "Inaccessible"
end

free_out = `free -b 2>/dev/null`.split("\n")
if $?.exitstatus == 0
  mem_line = free_out.find { |l| l.start_with?("Mem:") }&.split
  swap_line = free_out.find { |l| l.start_with?("Swap:") }&.split
  
  if mem_line
    resultats[:memoire] = {
      total: mem_line[1].to_i,
      utilise: mem_line[2].to_i,
      disponible: mem_line[6].to_i
    }
  end
  
  if swap_line
    resultats[:swap] = {
      total: swap_line[1].to_i,
      utilise: swap_line[2].to_i,
      libre: swap_line[3].to_i
    }
  end
end

ps_cpu = `ps -eo pid,user,%cpu,command --sort=-%cpu | head -n #{options[:top_n] + 1}`
if $?.exitstatus == 0
  lignes = ps_cpu.split("\n")
  lignes.shift 
  resultats[:top_cpu] = lignes.collect { |ligne| ligne.strip }
end

resultats[:services] = {}
options[:services].each do |service|
  actif = `systemctl is-active #{service} 2>/dev/null`.strip
  if service == 'ssh' && actif != 'active'
    actif_sock = `systemctl is-active ssh.socket 2>/dev/null`.strip
    actif = 'active (via socket)' if actif_sock == 'active'
  end
  active_status = actif.include?('active') ? actif : "inactif/erreur"
  
  boot = `systemctl is-enabled #{service} 2>/dev/null`.strip
  if service == 'ssh' && boot != 'enabled'
    boot_sock = `systemctl is-enabled ssh.socket 2>/dev/null`.strip
    boot = 'enabled (via socket)' if boot_sock == 'enabled'
  end
  boot_status = boot.include?('enabled') ? boot : "disabled/inconnu"
  
  resultats[:services][service] = { actif: active_status, demarrage: boot_status }
end

begin
  loadavg = File.read("#{options[:racine]}proc/loadavg").split[0..2]
  resultats[:load_average] = loadavg.join(" ")
rescue Exception
  resultats[:load_average] = "Inaccessible"
end

df_out = `df -P 2>/dev/null`
if $?.exitstatus == 0
  lignes_df = df_out.split("\n")
  lignes_df.shift 
  resultats[:disques] = lignes_df.collect do |ligne|
    colonnes = ligne.split
    { mount: colonnes[5], taille: colonnes[1], utilise: colonnes[2], dispo: colonnes[3] }
  end
end

ps_mem = `ps -eo pid,user,%mem,command --sort=-%mem | head -n #{options[:top_n] + 1}`
if $?.exitstatus == 0
  lignes_mem = ps_mem.split("\n")
  lignes_mem.shift
  resultats[:top_mem] = lignes_mem.collect { |ligne| ligne.strip }
end

begin
  min_uid, max_uid = 1000, 60000
  begin
    File.read("#{options[:racine]}etc/login.defs").each_line do |line|
      min_uid = $1.to_i if line.match(/^UID_MIN\s+(\d+)/)
      max_uid = $1.to_i if line.match(/^UID_MAX\s+(\d+)/)
    end
  rescue
  end

  utilisateurs = []
  File.read("#{options[:racine]}etc/passwd").each_line do |line|
    champs = line.split(':')
    uid = champs[2].to_i
    if uid >= min_uid && uid <= max_uid && uid != 65534
      utilisateurs << champs[0]
    end
  end
  
  connectes = `who 2>/dev/null`.split("\n").collect { |l| l.split[0] }.uniq
  resultats[:utilisateurs] = { humains: utilisateurs, connectes: connectes }
rescue Exception
  resultats[:utilisateurs] = "Erreur de lecture"
end

begin
  ip_json = `ip -j a 2>/dev/null`
  if $?.exitstatus == 0
    resultats[:interfaces] = JSON.parse(ip_json).collect do |iface|
      { nom: iface['ifname'], mac: iface['address'], ips: iface['addr_info'].collect { |a| a['local'] } }
    end
  end
rescue Exception
  resultats[:interfaces] = "Non disponible"
end

ss_out = `ss -H -t -u -n -p 2>/dev/null`
if $?.exitstatus == 0
  resultats[:connexions] = []
  ss_out.each_line do |l|
    parts = l.split
    resultats[:connexions] << { protocol: parts[0], state: parts[1], local: parts[4], peer: parts[5] } if parts.size >= 6
  end
end

if options[:json]
  resultats[:date_audit] = Time.now.to_s
  puts JSON.pretty_generate(resultats)
else
  puts "=== Audit Système (#{Time.now}) ==="
  puts "Machine : #{resultats[:hostname]}"
  puts "Distribution : #{resultats[:distribution]}"
  puts "Noyau : #{resultats[:noyau]}"
  puts "\n--- Services ---"
  resultats[:services].each do |nom, stats|
    puts "- #{nom} : #{stats[:actif]} (Démarrage: #{stats[:demarrage]})"
  end
end

