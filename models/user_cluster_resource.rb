class UserClusterResource < ActiveRecord::Base
  belongs_to :user
  belongs_to :environment
  belongs_to :cluster_resource

  def used
    return @used if @used

    @used = ::ClusterResourceUse.joins(:user_cluster_resource).where(
        user_cluster_resources: {
            user_id: user_id,
            environment_id: environment_id,
            cluster_resource_id: cluster_resource_id
        }
    ).sum(:value)
  end

  def free
    value - used
  end
end
