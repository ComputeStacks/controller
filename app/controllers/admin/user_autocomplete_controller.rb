##
# Partial-match user lookup for autocomplete inputs (e.g. the event log "Performed by" filter).
#
# GET /admin/users/autocomplete?q=jane => [{"id": 12, "label": "Jane Doe <jane@example.com>"}]
class Admin::UserAutocompleteController < Admin::ApplicationController
  LIMIT = 10

  def index
    render json: matching(params[:q].to_s.strip).map { |u| {id: u.id, label: u.full_name_with_email} }
  end

  private

  # Matches a user id exactly, or a substring of the email or full name. Needs two
  # characters of text so a single keystroke doesn't page through every user.
  def matching(q)
    numeric = q.match?(/\A\d+\z/)
    return User.none if q.length < 2 && !numeric
    like = "%#{User.sanitize_sql_like(q.downcase)}%"
    users = User.where("lower(users.email) LIKE :q OR lower(users.fname || ' ' || users.lname) LIKE :q", q: like)
    users = users.or(User.where(id: q.to_i)) if numeric
    users.sorted.limit(LIMIT)
  end
end
