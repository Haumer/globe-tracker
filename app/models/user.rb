class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :lockable, :timeoutable

  has_many :workspaces, dependent: :destroy
  has_many :watches, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :investigation_cases, dependent: :destroy
  has_many :assigned_investigation_cases, class_name: "InvestigationCase", foreign_key: :assignee_id, dependent: :nullify, inverse_of: :assignee
end
