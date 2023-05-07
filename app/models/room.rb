class Room < ApplicationRecord
  has_many :messages
  has_many :users

  validates_uniqueness_of :name
  scope :public_rooms, -> { where(is_private: false) }
  after_create_commit {broadcast_append_to "rooms"}

end
