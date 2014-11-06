class Node < ActiveRecord::Base
  self.table_name = 'servers'
  self.primary_key = 'server_id'

  belongs_to :location, :foreign_key => :server_location
  has_many :vpses, :foreign_key => :vps_server
  has_many :transactions, foreign_key: :t_server
  has_many :storage_roots
  has_many :pools
  has_many :vps_mounts, foreign_key: :server_id
  has_one :node_status, foreign_key: :server_id

  has_paper_trail

  alias_attribute :name, :server_name
  alias_attribute :addr, :server_ip4
  alias_attribute :vps_max, :max_vps

  validates :server_name, :server_type, :server_location, :server_ip4, presence: true
  validates :server_location, numericality: {only_integer: true}
  validates :server_name, format: {
      with: /\A[a-zA-Z0-9\.\-_]+\Z/,
      message: 'invalid format'
  }
  validates :server_type, inclusion: {
      in: %w(node storage mailer),
      message: '%{value} is not a valid node role'
  }
  validates :server_ip4, format: {
      with: /\A\d+\.\d+\.\d+\.\d+\Z/,
      message: 'not a valid IPv4 address'
  }

  after_update :shaper_changed, if: :shaper_changed?

  include VpsAdmin::API::Maintainable::Model
  maintenance_parent :location

  def location_domain
    "#{name}.#{location.domain}"
  end

  def fqdn
    "#{name}.#{location.fqdn}"
  end

  def self.pick_node_by_location_type(loc_type)
    self.joins('
      LEFT JOIN vps ON vps.vps_server = servers.server_id
      LEFT JOIN vps_status st ON st.vps_id = vps.vps_id
      INNER JOIN locations l ON server_location = location_id
    ').where('
      (st.vps_up = 1 OR st.vps_up IS NULL)
      AND max_vps > 0
      AND server_maintenance = 0
      AND location_type = ?
    ', loc_type).group('server_id')
    .order('COUNT(st.vps_up) / max_vps ASC')
    .take
  end

  def last_report
    node_status && Time.at(node_status.timestamp)
  end

  def loadavg
    node_status && node_status.cpu_load
  end

  def vps_running
    vpses.joins(:vps_status).where(vps_status: {vps_up: true}).count
  end

  def vps_stopped
    vpses.joins(:vps_status).where(vps_status: {vps_up: false}).count
  end

  def vps_deleted
    vpses.unscoped.where.not(vps_deleted: nil).count
  end

  def vps_total
    return @vps_total if @vps_total
    @vps_total = vpses.count
  end

  def vps_free
    max_vps - vps_total
  end

  def daemon_version
    node_status && node_status.vpsadmin_version
  end

  def kernel_version
    node_status && node_status.kernel
  end

  protected
  def shaper_changed?
    max_tx_changed? || max_rx_changed?
  end

  def shaper_changed
    Transactions::Vps::ShaperRootChange.fire(self) unless net_interface.nil?
  end
end
