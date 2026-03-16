class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :lockable, :timeoutable

  has_many :workspaces, dependent: :destroy
  has_many :watches, dependent: :destroy
  has_many :alerts, dependent: :destroy
end
