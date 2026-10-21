namespace :toolbox do
  desc "Render the site-wide share card to public/og-default.png"
  task default_og: :environment do
    path = Rails.public_path.join("og-default.png")
    # The file is committed, so it is quantised to a palette: a quarter of the size, same picture.
    Vips::Image.new_from_buffer(ProfileCard.site.render, "").write_to_file(path.to_s, palette: true, Q: 90)
    puts "Wrote #{path.relative_path_from(Rails.root)}"
  end

  desc "Remove a member who left Every (EMAIL=person@every.to): the same deletion as Settings, so their picks, history, suggestions, visibility periods, sessions and agent grants go too"
  task remove_member: :environment do
    email = ENV["EMAIL"].to_s.strip
    user = User.find_by(email_address: email) if email.present?
    abort "No member with the email #{email.inspect}. Usage: EMAIL=person@every.to bin/rails toolbox:remove_member" unless user

    user.destroy!
    puts "Removed #{user.email_address} and everything they had in Toolbox. Tools and models they added stay in the catalog."
  end

  desc "Revoke every agent connection and withdraw the suggestions agents left open; members connect and approve again"
  task revoke_agent_grants: :environment do
    now = Time.current
    grants = withdrawn = nil
    ApplicationRecord.transaction do
      grants = OauthGrant.where(revoked_at: nil).update_all(revoked_at: now, updated_at: now)
      OauthAuthorizationCode.where(used_at: nil).delete_all
      withdrawn = PickSuggestion.open.where.not(oauth_client_id: nil).update_all(status: "withdrawn", resolved_at: now, updated_at: now)
    end
    puts "Revoked #{grants} #{"grant".pluralize(grants)} and withdrew #{withdrawn} open #{"suggestion".pluralize(withdrawn)}."
  end
  desc "Add the Every team's personal-agent survey picks. Creates missing members, onboarded with a public page, whom their first Every sign-in adopts by email; leaves anyone who already has personal-agent picks alone"
  task import_personal_agents: :environment do
    # Personal agents the Every team named in the October 2026 survey, best first, by
    # catalog slug. Loop is unannounced-agent until it launches; a tie keeps the order
    # given. Mike Taylor uses none, and a self-built orchestrator is not in the catalog.
    survey = {
      "brandon@every.to" => [ "Brandon Gell", %w[instinct dots] ],
      "arielle@every.to" => [ "Arielle Shipper", %w[codex dots] ],
      "kate@every.to" => [ "Kate Lee", %w[dots] ],
      "dan@every.to" => [ "Dan Shipper", %w[dots unannounced-agent] ],
      "natalia@every.to" => [ "Natalia Quintero", %w[dots] ],
      "mike@every.to" => [ "Mike Taylor", [] ],
      "kaushik.viswanath@every.to" => [ "Kaushik Viswanath", %w[dots instinct] ],
      "loren.stewart@every.to" => [ "Loren Stewart", %w[dots] ],
      "lee@every.to" => [ "Lee Knowlton", %w[dots grok-bot] ],
      "jannik@every.to" => [ "Jannik Jung", %w[poke instinct dots] ],
      "andrey@every.to" => [ "Andrey Galko", %w[poke] ],
      "micah.rich@every.to" => [ "Micah Rich", %w[instinct poke grok-bot] ],
      "becky@every.to" => [ "Becky Isjwara", %w[dots] ],
      "daniel@every.to" => [ "Daniel Rodrigues", %w[dots] ],
      "laura@every.to" => [ "Laura Entis", %w[dots] ],
      "katie@every.to" => [ "Katie Parrott", %w[dots] ],
      "randy.counsman@every.to" => [ "Randy Counsman", %w[dots instinct] ],
      "ryan@every.to" => [ "Ryan Wright", %w[dots unannounced-agent grok-bot] ],
      "tyler.nishida@every.to" => [ "Tyler Nishida", %w[grok-bot unannounced-agent] ],
      "brian@every.to" => [ "Brian Dell", %w[dots instinct] ],
      "diana@every.to" => [ "Diana Palacio", %w[codex grok-bot] ],
      "waqqas@every.to" => [ "Waqqas Mir", %w[grok-bot] ]
    }

    survey.each do |email, (name, tools)|
      user = User.find_or_initialize_by(email_address: email)
      if user.new_record?
        user.update!(name:, email_verified: true, handle: User.suggest_handle(from: email), onboarded_at: Time.current, visibility: "link")
      end

      category = Category.find_by!(slug: "personal-agents")
      if user.entries.where(category:).exists?
        puts "Skipped #{email}: already has personal-agent picks"
        next
      end
      next puts("Added #{email} with no picks") if tools.empty?

      operations = tools.each_with_index.map { |tool, index| { op: "set_pick", category: category.slug, rank: index + 1, tool: } }
      Toolbox::Update.call(user:, operations:, source: "web")
      puts "Added #{email}: #{tools.join(", ")}"
    end
  end
  desc "On Claude Duet's launch day, after the deploy that names it: give the Duet picks without a model Claude Opus 5.5, which it is built around"
  task launch_duet: :environment do
    duet = Tool.find_by!(slug: "unannounced-agent")
    abort "Deploy the catalog that names Claude Duet first (it is still #{duet.name.inspect})." unless duet.name == "Claude Duet"

    duet.entries.where(ai_model_id: nil).includes(:user, :category).find_each do |entry|
      Toolbox::Update.call(user: entry.user, source: "web",
        operations: [ { op: "set_pick", category: entry.category.slug, rank: entry.rank, model: "claude-opus-5-5", expected_tool: duet.slug } ])
      puts "#{entry.user.email_address}: Claude Duet at ##{entry.rank} now runs Claude Opus 5.5"
    end
  end
end
