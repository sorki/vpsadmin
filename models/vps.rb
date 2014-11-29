class Vps < ActiveRecord::Base
  self.table_name = 'vps'
  self.primary_key = 'vps_id'

  belongs_to :node, :foreign_key => :vps_server
  belongs_to :user, :foreign_key => :m_id
  belongs_to :os_template, :foreign_key => :vps_template
  belongs_to :dns_resolver
  has_many :ip_addresses
  has_many :transactions, foreign_key: :t_vps

  has_many :vps_has_config, -> { order '`order`' }
  has_many :vps_configs, through: :vps_has_config
  has_many :vps_mounts, dependent: :delete_all

  belongs_to :dataset_in_pool
  has_many :mounts

  has_one :vps_status

  has_paper_trail

  alias_attribute :veid, :vps_id
  alias_attribute :hostname, :vps_hostname
  alias_attribute :user_id, :m_id

  validates :m_id, :vps_server, :vps_template, presence: true, numericality: {only_integer: true}
  validates :vps_hostname, presence: true, format: {
      with: /[a-zA-Z\-_\.0-9]{0,255}/,
      message: 'bad format'
  }
  validate :foreign_keys_exist

  default_scope { where(vps_deleted: nil) }

  include Lockable
  include Confirmable
  include HaveAPI::Hookable

  has_hook :create

  include VpsAdmin::API::Maintainable::Model
  maintenance_parent :node

  PathInfo = Struct.new(:dataset, :exists)

  def create(add_ips)
    self.vps_backup_export = 0 # FIXME
    self.vps_backup_exclude = '' # FIXME
    self.vps_config = ''

    lifetime = self.user.env_config(
        node.location.environment,
        :vps_lifetime
    )

    self.vps_expiration = Time.new.to_i + lifetime if lifetime != 0

    self.dns_resolver_id ||= DnsResolver.pick_suitable_resolver_for_vps(self).id

    if valid?
      TransactionChains::Vps::Create.fire(self, add_ips)
    else
      false
    end
  end

  def lazy_delete(lazy)
    if lazy
      self.vps_deleted = Time.new.to_i
      save!
      stop
    else
      destroy
    end
  end

  def destroy(override = false)
    if override
      super
    else
      TransactionChains::Vps::Destroy.fire(self)
    end
  end

  # Filter attributes that must be changed by a transaction.
  def update(attributes)
    assign_attributes(attributes)
    return false unless valid?

    to_change = {}

    %w(vps_hostname vps_template dns_resolver_id).each do |attr|
      if changed.include?(attr)
        if attr.ends_with?('_id')
          to_change[attr] = send(attr[0..-4])
        else
          to_change[attr] = send(attr)
        end

        send("#{attr}=", changed_attributes[attr])
      end
    end

    unless to_change.empty?
      TransactionChains::Vps::Update.fire(self, to_change)
    end

    (changed? && save) || true
  end

  def start
    TransactionChains::Vps::Start.fire(self)
  end

  def restart
    TransactionChains::Vps::Restart.fire(self)
  end

  def stop
    TransactionChains::Vps::Stop.fire(self)
  end

  def applyconfig(configs)
    TransactionChains::Vps::ApplyConfig.fire(self, configs)
  end

  def revive
    self.vps_deleted = nil
  end

  # Unless +safe+ is true, the IP address +ip+ is fetched from the database
  # again in a transaction, to ensure that it has not been given
  # to any other VPS. Set +safe+ to true if +ip+ was fetched in a transaction.
  def add_ip(ip, safe = false)
    ::IpAddress.transaction do
      ip = ::IpAddress.find(ip.id) unless safe

      unless ip.ip_location == node.server_location
        raise VpsAdmin::API::Exceptions::IpAddressInvalidLocation
      end

      raise VpsAdmin::API::Exceptions::IpAddressInUse unless ip.free?

      TransactionChains::Vps::AddIp.fire(self, [ip])
    end
  end

  def add_free_ip(v)
    ::IpAddress.transaction do
      ip = ::IpAddress.pick_addr!(node.location, v)
      add_ip(ip, true)
    end

    ip
  end

  # See #add_ip for more information about +safe+.
  def delete_ip(ip, safe = false)
    ::IpAddress.transaction do
      ip = ::IpAddress.find(ip.id) unless safe

      unless ip.vps_id == self.id
        raise VpsAdmin::API::Exceptions::IpAddressNotAssigned
      end

      TransactionChains::Vps::DelIp.fire(self, [ip])
    end
  end

  def delete_ips(v=nil)
    ::IpAddress.transaction do
      if v
        ips = ip_addresses.where(ip_v: v)
      else
        ips = ip_addresses.all
      end

      TransactionChains::Vps::DelIp.fire(self, ips)
    end
  end

  def passwd
    pass = generate_password

    TransactionChains::Vps::Passwd.fire(self, pass)

    pass
  end

  def reinstall(template)
    TransactionChains::Vps::Reinstall.fire(self, template)
  end

  def restore(snapshot)
    TransactionChains::Vps::Restore.fire(self, snapshot)
  end

  def running
    vps_status && vps_status.vps_up
  end

  def process_count
    vps_status && vps_status.vps_nproc
  end

  def used_memory
    vps_status && vps_status.vps_vm_used_mb
  end

  def used_disk
    vps_status && vps_status.vps_disk_used_mb
  end

  # All datasets in path except the last have the default
  # mountpoint. +mountpoint+ is relevant only for the last
  # dataset in path.
  # FIXME: subdatasets must be mounted via vzctl action scripts,
  #        zfs set canmount=noauto and add to veid.(u)mount.
  def create_subdataset(path, mountpoint)
    last, parts = dataset_create_path(path)

    if last
      dip = last.dataset_in_pools.joins(:pool).where(pools: {role: Pool.roles[:hypervisor]}).take
      mnt = dip.mountpoint if dip
    else
      mnt = nil
    end

    mountpoints = []

    last_mountpoint = prefix_mountpoint(mnt, nil, nil)

    parts[0..-2].each do |part|
      last_mountpoint = prefix_mountpoint(last_mountpoint, part, nil)

      mountpoints << last_mountpoint
    end

    mountpoints << prefix_mountpoint(last_mountpoint, parts.last, mountpoint)

    TransactionChains::Dataset::Create.fire(
        dataset_in_pool,
        parts,
        mountpoints
    )
  end

  def destroy_subdataset(dataset)
    TransactionChains::DatasetInPool::Destroy.fire(
        dataset.dataset_in_pools.joins(:pool).where(pools: {role: ::Pool.roles[:hypervisor]}).take!,
        true
    )
  end

  private
  def generate_password
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a
    (0..19).map { chars.sample }.join
  end

  def foreign_keys_exist
    User.find(user_id)
    Node.find(vps_server)
    OsTemplate.find(vps_template)
    DnsResolver.find(dns_resolver_id)
  end

  def create_default_mounts(mapping)
    VpsMount.default_mounts.each do |m|
      mnt = VpsMount.new(m.attributes)
      mnt.id = nil
      mnt.default = false
      mnt.vps = self if mnt.vps_id == 0 || mnt.vps_id.nil?

      unless m.storage_export_id.nil? || m.storage_export_id == 0
        export = StorageExport.find(m.storage_export_id)

        mnt.storage_export_id = mapping[export.id] if export.default != 'no'
      end

      mnt.save!
    end
  end

  def delete_mounts
    self.vps_mounts.delete(self.vps_mounts.all)
  end

  def prefix_mountpoint(parent, part, mountpoint)
    root = ['/', 'vz', 'root', veid.to_s]

    return File.join(parent) if parent && !part
    return File.join(*root) unless part

    if mountpoint
      File.join(*root, mountpoint)

    elsif parent
      File.join(parent, part.name)
    end
  end

  def dataset_create_path(path)
    parts = path.split('/')
    tmp = dataset_in_pool.dataset
    ret = []
    last = nil

    if parts.empty?
      ds = Dataset.new
      ds.valid?
      raise ::ActiveRecord::RecordInvalid, ds
    end

    parts.each do |part|
      # As long as tmp is not nil, we're iterating over existing datasets.
      if tmp
        ds = tmp.children.find_by(name: part)

        if ds
          # Add the dataset to ret if it is NOT present on pool with hypervisor role.
          # It means that the dataset was destroyed and is presumably only in backup.
          if ds.dataset_in_pools.joins(:pool).where(pools: {role: Pool.roles[:hypervisor]}).pluck(:id).empty?
            ret << ds
          else
            last = ds
          end

          tmp = ds

        else
          ret << dataset_create_append_new(part, tmp)
          tmp = nil
        end

      else
        ret << dataset_create_append_new(part, nil)
      end
    end

    if ret.empty?
      raise VpsAdmin::API::Exceptions::DatasetAlreadyExists.new(tmp, parts.join('/'))
    end

    [last, ret]
  end

  def dataset_create_append_new(part, parent)
    new_ds = ::Dataset.new(
        name: part,
        user: User.current,
        user_editable: true,
        user_create: true,
        confirmed: ::Dataset.confirmed(:confirm_create)
    )

    new_ds.parent = parent if parent

    raise ::ActiveRecord::RecordInvalid, new_ds unless new_ds.valid?

    new_ds
  end

  def dataset_to_destroy(path)
    parts = path.split('/')
    parent = dataset_in_pool.dataset
    dip = nil

    parts.each do |part|
      ds = parent.children.find_by(name: part)

      if ds
        parent = ds
        dip = ds.dataset_in_pools.joins(:pool).where(pools: {role: Pool.roles[:hypervisor]}).take

        unless dip
          raise VpsAdmin::API::Exceptions::DatasetDoesNotExist, path
        end

      else
        raise VpsAdmin::API::Exceptions::DatasetDoesNotExist, path
      end
    end

    dip
  end
end
