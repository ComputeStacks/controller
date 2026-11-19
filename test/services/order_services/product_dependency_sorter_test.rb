require "test_helper"
require "minitest/mock"

##
# Fixtures: wordpress depends on mariadb (role "mysql"); pma and elasticsearch are unrelated.
class OrderServices::ProductDependencySorterTest < ActiveSupport::TestCase
  def product(variant, label = variant.to_s)
    variant_id = variant.is_a?(Symbol) ? container_image_image_variants(variant).id : variant
    {product_type: "container", image_variant_id: variant_id, label: label}.with_indifferent_access
  end

  def labels(products)
    OrderServices::ProductDependencySorter.new(products).perform.map { |p| p[:label] }
  end

  def link!(image, dependency)
    ContainerImage::ImageRel.create!(
      container_image: container_images(image),
      dependency: container_images(dependency),
      bypass_auth_check: true
    )
  end

  test "a dependency matched by image id comes first" do
    assert_equal %w[mariadb_default wordpress_default pma_default],
      labels([product(:wordpress_default), product(:mariadb_default), product(:pma_default)])
  end

  # init_link! accepts any image with the dependency's role, so the sort must too.
  test "a dependency matched by role comes first" do
    container_images(:pma).update_column :role, "mysql"

    assert_equal %w[pma_default wordpress_default],
      labels([product(:wordpress_default), product(:pma_default)])
  end

  test "unrelated products keep their original order" do
    assert_equal %w[elasticsearch_default pma_default nginx_default],
      labels([product(:elasticsearch_default), product(:pma_default), product(:nginx_default)])
    assert_equal %w[pma_default mariadb_default wordpress_default],
      labels([product(:pma_default), product(:mariadb_default), product(:wordpress_default)])
  end

  test "a multi-level chain is ordered end to end" do
    link!(:pma, :wordpress)

    assert_equal %w[mariadb_default wordpress_default pma_default],
      labels([product(:pma_default), product(:wordpress_default), product(:mariadb_default)])
  end

  test "a cycle keeps its members in their original order" do
    link!(:mariadb, :wordpress)

    assert_equal %w[pma_default wordpress_default mariadb_default],
      labels([product(:pma_default), product(:wordpress_default), product(:mariadb_default)])
    assert_equal %w[mariadb_default wordpress_default],
      labels([product(:mariadb_default), product(:wordpress_default)])
  end

  # The cycle is one group: whatever depends on it still comes after all of it.
  test "a product depending on a cycle comes after the cycle" do
    link!(:mariadb, :wordpress)
    link!(:pma, :mariadb)

    assert_equal %w[wordpress_default mariadb_default pma_default],
      labels([product(:pma_default), product(:wordpress_default), product(:mariadb_default)])
  end

  test "an unresolvable image or a non-container product stays where it was" do
    products = [
      product(0, "missing"),
      {product_type: "addon", label: "addon"}.with_indifferent_access,
      product(:wordpress_default),
      product(:mariadb_default)
    ]

    assert_equal %w[missing addon mariadb_default wordpress_default], labels(products)
  end

  test "identical products are both kept, as the same objects" do
    a = product(:pma_default)
    b = product(:pma_default)
    sorted = OrderServices::ProductDependencySorter.new([a, b]).perform

    assert_equal 2, sorted.length
    assert sorted[0].equal?(a)
    assert sorted[1].equal?(b)
  end

  test "never raises" do
    products = [product(:wordpress_default), product(:mariadb_default)]
    ContainerImage::ImageVariant.stub(:find_by, ->(*) { raise "boom" }) do
      ExceptionAlertService.stub(:new, ->(*) { Struct.new(:perform).new(true) }) do
        assert_equal %w[wordpress_default mariadb_default],
          labels(products)
      end
    end
  end
end
