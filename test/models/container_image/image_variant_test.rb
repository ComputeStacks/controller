require "test_helper"

class ContainerImage::ImageVariantTest < ActiveSupport::TestCase

  test 'default variant lifecycle' do

    image = ContainerImage.new(
      name: 'mysql_variant_test',
      label: 'MySQL Test',
      category: 'database',
      role: 'mysql',
      registry_image_path: 'mysql',
      registry_image_tag: '8.0'
    )
    image.save
    unless image.errors.empty?
      puts image.errors.full_messages
    end
    assert_empty image.errors

    initial_variant = image.image_variants.first

    new_variant = image.image_variants.new(
      label: '5.7',
      registry_image_tag: '5.7'
    )
    new_variant.save
    unless new_variant.errors.empty?
      puts new_variant.errors.full_messages
    end
    assert_empty new_variant.errors

    assert_equal 1, image.image_variants.default.count

    refute_includes image.image_variants.default, new_variant

    assert new_variant.update(is_default: true)

    new_variant.reload
    image.reload

    assert_equal 1, image.image_variants.default.count

    assert_includes image.image_variants.default, new_variant
    refute_includes image.image_variants.default, initial_variant

  end

end
