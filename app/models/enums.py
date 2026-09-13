import enum


class UserRole(str, enum.Enum):
    citizen = "citizen"
    university = "university"
    industry = "industry"
    admin = "admin"


class ChallengeStatus(str, enum.Enum):
    submitted = "Submitted"
    under_review = "Under Review"
    assigned = "Assigned"
    in_progress = "In Progress"
    solution_deployed = "Solution Deployed"
    resolved = "Resolved"
    rejected = "Rejected"
    duplicate = "Duplicate"


class Priority(str, enum.Enum):
    high = "High"
    medium = "Medium"
    low = "Low"


class MilestoneStatus(str, enum.Enum):
    pending = "Pending"
    in_progress = "In Progress"
    submitted = "Submitted"
    approved = "Approved"
    rejected = "Rejected"


class ProjectStatus(str, enum.Enum):
    proposed = "Proposed"
    active = "Active"
    completed = "Completed"
    cancelled = "Cancelled"


class MatchStatus(str, enum.Enum):
    suggested = "Suggested"
    assigned = "Assigned"
    accepted = "Accepted"
    declined = "Declined"


class InterestStatus(str, enum.Enum):
    pending = "Pending"
    accepted = "Accepted"
    declined = "Declined"
