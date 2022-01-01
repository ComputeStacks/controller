class RegionPackageValidator < ActiveModel::Validator
  def validate(region_package)
    unless region_package.id && RegionPackage.find_by(id: region_package.id)&.region_id == region_package.region_id
      if RegionPackage.where(region_id: region_package.region_id, billing_package_id: region_package.billing_package.id).exists?
        region_package.errors.add(:base, "The billing package is already assigned to the specified region.")
      end
    end
  end
end