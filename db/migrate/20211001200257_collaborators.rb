class Collaborators < ActiveRecord::Migration[6.1]
  def change

    create_table :deployment_collaborators do |t|
      t.bigint :deployment_id
      t.bigint :user_id
      t.boolean :active, null: false, default: false

      t.timestamps
    end
    add_index :deployment_collaborators, [:deployment_id, :user_id], unique: true
    add_index :deployment_collaborators, :active

    create_table :container_registry_collaborators do |t|
      t.bigint :container_registry_id
      t.bigint :user_id
      t.boolean :active, null: false, default: false

      t.timestamps
    end
    add_index :container_registry_collaborators, [:container_registry_id, :user_id], unique: true, name: 'cr_collab_reg_user'
    add_index :container_registry_collaborators, :active

    create_table :container_image_collaborators do |t|
      t.bigint :container_image_id
      t.bigint :user_id
      t.boolean :active, null: false, default: false

      t.timestamps
    end
    add_index :container_image_collaborators, [:container_image_id, :user_id], unique: true, name: 'image_collab_img_user'
    add_index :container_image_collaborators, :active

    create_table :dns_zone_collaborators do |t|
      t.bigint :dns_zone_id
      t.bigint :user_id
      t.boolean :active, null: false, default: false

      t.timestamps
    end
    add_index :dns_zone_collaborators, [:dns_zone_id, :user_id], unique: true
    add_index :dns_zone_collaborators, :active

    unless Block.where(content_key: 'collaborate.warning').exists?
      puts "...Collaborate: Warning..."
      block_collaborate = Block.create!(title: 'Collaborate: Warning', content_key: 'collaborate.warning')
      block_collaborate.block_contents.create!(
        locale: ENV['LOCALE'].blank? ? 'en' : ENV['LOCALE'],
        body: %Q(<div><strong>Warning!</strong> Any collaborator you add will have the same permissions as you!</div>)
      )
      block_faq = Block.create!(title: 'Collaborate: FAQ', content_key: 'collaborate.faq')
      block_faq.block_contents.create!(
        locale: ENV['LOCALE'].blank? ? 'en' : ENV['LOCALE'],
        body: %Q(<div>Collaborators will be able to edit and manage this resource, as well as, create and delete any child resources. Any billable action they take will be billed to the resource owner's account.</div>)
      )
    end

    unless Block.where(content_key: 'collaborate.invite.registry').exists?
      puts "...Collaborate: Invitation - Registry..."
      block_collaborate = Block.create!(title: 'Collaborate: Registry Invite', content_key: 'collaborate.invite.registry')
      block_collaborate.block_contents.create!(
        locale: ENV['LOCALE'],
        body: %Q(<h4>Container Registry Collaboration Invite</h4><div>{{ user }} has invited you to collaborate on the container registry {{ registry }}. Please click the link below to accept or reject this invitation.</div>)
      )
    end

    unless Block.where(content_key: 'collaborate.invite.project').exists?
      puts "...Collaborate: Invitation - Project..."
      block_collaborate = Block.create!(title: 'Collaborate: Project Invite', content_key: 'collaborate.invite.project')
      block_collaborate.block_contents.create!(
        locale: ENV['LOCALE'],
        body: %Q(<h4>Project Collaboration Invite</h4><div>{{ user }} has invited you to collaborate on the project {{ project }}. Please click the link below to accept or reject this invitation.</div>)
      )
    end

    unless Block.where(content_key: 'collaborate.invite.image').exists?
      puts "...Collaborate: Invitation - Image..."
      block_collaborate = Block.create!(title: 'Collaborate: Image Invite', content_key: 'collaborate.invite.image')
      block_collaborate.block_contents.create!(
        locale: ENV['LOCALE'],
        body: %Q(<h4>Container Image Collaboration Invite</h4><div>{{ user }} has invited you to collaborate on the image {{ image }}. Please click the link below to accept or reject this invitation.</div>)
      )
    end

    unless Block.where(content_key: 'collaborate.invite.domain').exists?
      puts "...Collaborate: Invitation - DNS Zone..."
      block_collaborate = Block.create!(title: 'Collaborate: DNS Zone Invite', content_key: 'collaborate.invite.domain')
      block_collaborate.block_contents.create!(
        locale: ENV['LOCALE'],
        body: %Q(<h4>DNS Zone Collaboration Invite</h4><div>{{ user }} has invited you to collaborate on the zone {{ domain }}. Please click the link below to accept or reject this invitation.</div>)
      )
    end

  end
end
