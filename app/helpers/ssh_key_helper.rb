module SshKeyHelper

  def ssh_key_algo_badge(k)
    case k.public_key.algo
    when "ssh-ed25519"
      tag.span("ed25519", class: "label label-info")
    else
      tag.span(k.public_key.algo, class: "label label-warning")
    end
  rescue
    ""
  end

end
