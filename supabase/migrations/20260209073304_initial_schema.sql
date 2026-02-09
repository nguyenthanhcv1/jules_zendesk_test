-- === BẢNG 1: profiles ===
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'qa_lead', 'qa_reviewer')) DEFAULT 'qa_reviewer',
    is_active BOOLEAN DEFAULT true,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can read all active profiles
CREATE POLICY "Profiles are viewable by authenticated users"
ON public.profiles FOR SELECT
TO authenticated
USING (is_active = true);

-- Only admin can insert/delete/update role
-- For non-admins, they can only update their own profile and cannot change role
CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (
    auth.uid() = id
    AND (
        role = (SELECT role FROM public.profiles WHERE id = auth.uid())
    )
);

CREATE POLICY "Admin full access on profiles"
ON public.profiles FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    )
);

-- Triggers
-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), 'qa_reviewer');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Update updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER set_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- === BẢNG 3: ai_providers ===
CREATE TABLE IF NOT EXISTS public.ai_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    base_url TEXT NOT NULL,
    auth_type TEXT DEFAULT 'bearer' CHECK (auth_type IN ('bearer', 'x-api-key', 'query_param')),
    auth_header TEXT DEFAULT 'Authorization',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ai_providers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated can read active providers"
ON public.ai_providers FOR SELECT
TO authenticated
USING (is_active = true);

CREATE POLICY "Only admin can modify providers"
ON public.ai_providers FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    )
);

-- Seed data for ai_providers
INSERT INTO public.ai_providers (name, slug, base_url, auth_type, auth_header)
VALUES
    ('Anthropic', 'anthropic', 'https://api.anthropic.com', 'x-api-key', 'x-api-key'),
    ('OpenAI', 'openai', 'https://api.openai.com/v1', 'bearer', 'Authorization'),
    ('Google Gemini', 'google-gemini', 'https://generativelanguage.googleapis.com', 'x-api-key', 'x-goog-api-key'),
    ('Groq', 'groq', 'https://api.groq.com/openai/v1', 'bearer', 'Authorization'),
    ('OpenRouter', 'openrouter', 'https://openrouter.ai/api/v1', 'bearer', 'Authorization')
ON CONFLICT (slug) DO UPDATE SET
    base_url = EXCLUDED.base_url,
    auth_type = EXCLUDED.auth_type,
    auth_header = EXCLUDED.auth_header;

-- === BẢNG 4: ai_models ===
CREATE TABLE IF NOT EXISTS public.ai_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID REFERENCES public.ai_providers(id) ON DELETE CASCADE,
    model_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    context_window INT,
    cost_per_1k_input DECIMAL(10,6),
    cost_per_1k_output DECIMAL(10,6),
    tier TEXT DEFAULT 'standard' CHECK (tier IN ('fast', 'standard', 'premium')),
    capabilities JSONB DEFAULT '[]',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(provider_id, model_id)
);

ALTER TABLE public.ai_models ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated can read active models"
ON public.ai_models FOR SELECT
TO authenticated
USING (is_active = true);

CREATE POLICY "Only admin can modify models"
ON public.ai_models FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    )
);

-- Seed data for ai_models
DO $$
DECLARE
    anthropic_id UUID;
    openai_id UUID;
    google_id UUID;
    groq_id UUID;
    openrouter_id UUID;
BEGIN
    SELECT id INTO anthropic_id FROM public.ai_providers WHERE slug = 'anthropic';
    SELECT id INTO openai_id FROM public.ai_providers WHERE slug = 'openai';
    SELECT id INTO google_id FROM public.ai_providers WHERE slug = 'google-gemini';
    SELECT id INTO groq_id FROM public.ai_providers WHERE slug = 'groq';
    SELECT id INTO openrouter_id FROM public.ai_providers WHERE slug = 'openrouter';

    -- Anthropic
    INSERT INTO public.ai_models (provider_id, model_id, display_name, context_window, cost_per_1k_input, cost_per_1k_output, tier)
    VALUES
        (anthropic_id, 'claude-3-5-sonnet-20240620', 'Claude 3.5 Sonnet', 200000, 0.003, 0.015, 'standard'),
        (anthropic_id, 'claude-3-opus-20240229', 'Claude 3 Opus', 200000, 0.015, 0.075, 'premium')
    ON CONFLICT (provider_id, model_id) DO NOTHING;

    -- OpenAI
    INSERT INTO public.ai_models (provider_id, model_id, display_name, context_window, cost_per_1k_input, cost_per_1k_output, tier)
    VALUES
        (openai_id, 'gpt-4o', 'GPT-4o', 128000, 0.005, 0.015, 'standard'),
        (openai_id, 'gpt-4-turbo', 'GPT-4 Turbo', 128000, 0.01, 0.03, 'premium')
    ON CONFLICT (provider_id, model_id) DO NOTHING;

    -- Google
    INSERT INTO public.ai_models (provider_id, model_id, display_name, context_window, cost_per_1k_input, cost_per_1k_output, tier)
    VALUES
        (google_id, 'gemini-1.5-pro', 'Gemini 1.5 Pro', 1000000, 0.0035, 0.0105, 'premium'),
        (google_id, 'gemini-1.5-flash', 'Gemini 1.5 Flash', 1000000, 0.00035, 0.00105, 'fast')
    ON CONFLICT (provider_id, model_id) DO NOTHING;

    -- Groq
    INSERT INTO public.ai_models (provider_id, model_id, display_name, context_window, cost_per_1k_input, cost_per_1k_output, tier)
    VALUES
        (groq_id, 'llama3-70b-8192', 'Llama 3 70B', 8192, 0.0007, 0.0008, 'fast'),
        (groq_id, 'mixtral-8x7b-32768', 'Mixtral 8x7B', 32768, 0.00027, 0.00027, 'fast')
    ON CONFLICT (provider_id, model_id) DO NOTHING;

    -- OpenRouter
    INSERT INTO public.ai_models (provider_id, model_id, display_name, context_window, cost_per_1k_input, cost_per_1k_output, tier)
    VALUES
        (openrouter_id, 'anthropic/claude-3.5-sonnet', 'Claude 3.5 Sonnet (OR)', 200000, 0.003, 0.015, 'standard'),
        (openrouter_id, 'openai/gpt-4o', 'GPT-4o (OR)', 128000, 0.005, 0.015, 'standard')
    ON CONFLICT (provider_id, model_id) DO NOTHING;
END $$;

-- === BẢNG 2: zendesk_configs ===
CREATE TABLE IF NOT EXISTS public.zendesk_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subdomain TEXT NOT NULL,
    admin_email TEXT NOT NULL,
    api_token TEXT NOT NULL,
    label TEXT,
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.zendesk_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admin can CRUD zendesk_configs"
ON public.zendesk_configs FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    )
);

-- === BẢNG 5: ai_api_keys ===
CREATE TABLE IF NOT EXISTS public.ai_api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID REFERENCES public.ai_providers(id),
    encrypted_key TEXT NOT NULL,
    label TEXT,
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    last_used_at TIMESTAMPTZ
);

ALTER TABLE public.ai_api_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admin can CRUD ai_api_keys"
ON public.ai_api_keys FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    )
);

-- === BẢNG 6: ai_evaluation_configs ===
CREATE TABLE IF NOT EXISTS public.ai_evaluation_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    model_id UUID REFERENCES public.ai_models(id),
    temperature DECIMAL(3,2) DEFAULT 0.1,
    max_tokens INT DEFAULT 4096,
    system_prompt TEXT,
    is_default BOOLEAN DEFAULT false,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ai_evaluation_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated can read ai_evaluation_configs"
ON public.ai_evaluation_configs FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admin and qa_lead can modify ai_evaluation_configs"
ON public.ai_evaluation_configs FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'qa_lead')
    )
);

-- === BẢNG 7: scorecards ===
CREATE TABLE IF NOT EXISTS public.scorecards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_by UUID REFERENCES public.profiles(id),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.scorecards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated can read active scorecards"
ON public.scorecards FOR SELECT
TO authenticated
USING (is_active = true);

CREATE POLICY "Admin and qa_lead can CRUD scorecards"
ON public.scorecards FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'qa_lead')
    )
);

CREATE OR REPLACE TRIGGER set_scorecards_updated_at
    BEFORE UPDATE ON public.scorecards
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- === BẢNG 8: scorecard_criteria ===
CREATE TABLE IF NOT EXISTS public.scorecard_criteria (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scorecard_id UUID REFERENCES public.scorecards(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    weight DECIMAL(5,2) NOT NULL,
    max_score INT NOT NULL DEFAULT 5,
    rubric JSONB NOT NULL DEFAULT '{}',
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.scorecard_criteria ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Criteria follows scorecard permissions for select"
ON public.scorecard_criteria FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.scorecards
        WHERE id = scorecard_id AND is_active = true
    )
);

CREATE POLICY "Criteria follows scorecard permissions for modify"
ON public.scorecard_criteria FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'qa_lead')
    )
);


-- === BẢNG 9: evaluations ===
CREATE TABLE IF NOT EXISTS public.evaluations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id TEXT NOT NULL,
    ticket_subject TEXT,
    ticket_url TEXT,
    agent_name TEXT,
    agent_email TEXT,
    scorecard_id UUID REFERENCES public.scorecards(id),
    ai_config_id UUID REFERENCES public.ai_evaluation_configs(id),
    overall_score DECIMAL(5,2),
    status TEXT DEFAULT 'pending_review' CHECK (status IN ('pending_review', 'approved', 'disputed', 'overridden')),
    evaluated_by TEXT NOT NULL,
    model_used TEXT,
    tokens_input INT,
    tokens_output INT,
    ai_latency_ms INT,
    ai_cost DECIMAL(10,6),
    ai_raw_response JSONB,
    highlights JSONB DEFAULT '[]',
    improvement_areas JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT now(),
    reviewed_by UUID REFERENCES public.profiles(id),
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT
);

ALTER TABLE public.evaluations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated can read evaluations"
ON public.evaluations FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "All authenticated can create evaluations"
ON public.evaluations FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Admin and qa_lead can update status"
ON public.evaluations FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'qa_lead')
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'qa_lead')
    )
);

-- === BẢNG 10: evaluation_scores ===
CREATE TABLE IF NOT EXISTS public.evaluation_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    evaluation_id UUID REFERENCES public.evaluations(id) ON DELETE CASCADE,
    criteria_id UUID REFERENCES public.scorecard_criteria(id),
    score DECIMAL(5,2) NOT NULL,
    reasoning TEXT,
    evidence JSONB DEFAULT '[]',
    suggestion TEXT,
    override_score DECIMAL(5,2),
    override_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.evaluation_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Scores follow evaluation permissions for select"
ON public.evaluation_scores FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Scores follow evaluation permissions for insert"
ON public.evaluation_scores FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Admin and qa_lead can update scores"
ON public.evaluation_scores FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'qa_lead')
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'qa_lead')
    )
);

-- === BẢNG 11: policy_documents ===
CREATE TABLE IF NOT EXISTS public.policy_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT,
    is_active BOOLEAN DEFAULT true,
    uploaded_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.policy_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated can read active policy documents"
ON public.policy_documents FOR SELECT
TO authenticated
USING (is_active = true);

CREATE POLICY "Admin and qa_lead can CRUD policy documents"
ON public.policy_documents FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'qa_lead')
    )
);

CREATE OR REPLACE TRIGGER set_policy_documents_updated_at
    BEFORE UPDATE ON public.policy_documents
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- === INDEXES ===
CREATE INDEX IF NOT EXISTS idx_evaluations_ticket_id ON public.evaluations(ticket_id);
CREATE INDEX IF NOT EXISTS idx_evaluations_agent_email ON public.evaluations(agent_email);
CREATE INDEX IF NOT EXISTS idx_evaluations_status ON public.evaluations(status);
CREATE INDEX IF NOT EXISTS idx_evaluations_created_at ON public.evaluations(created_at);
CREATE INDEX IF NOT EXISTS idx_evaluation_scores_evaluation_id ON public.evaluation_scores(evaluation_id);
CREATE INDEX IF NOT EXISTS idx_scorecard_criteria_scorecard_id ON public.scorecard_criteria(scorecard_id);

-- === VIEWS ===
-- View "evaluation_summary" join evaluations + evaluation_scores + scorecard_criteria
CREATE OR REPLACE VIEW public.evaluation_summary AS
SELECT
    e.id AS evaluation_id,
    e.ticket_id,
    e.ticket_subject,
    e.agent_name,
    e.agent_email,
    e.overall_score,
    e.status,
    e.created_at AS evaluated_at,
    s.name AS scorecard_name,
    sc.name AS criteria_name,
    sc.weight AS criteria_weight,
    es.score AS criteria_score,
    es.reasoning AS criteria_reasoning,
    es.override_score AS criteria_override_score
FROM public.evaluations e
JOIN public.scorecards s ON e.scorecard_id = s.id
JOIN public.evaluation_scores es ON e.id = es.evaluation_id
JOIN public.scorecard_criteria sc ON es.criteria_id = sc.id;

-- View "ai_cost_summary" group by month, model, provider
CREATE OR REPLACE VIEW public.ai_cost_summary AS
SELECT
    DATE_TRUNC('month', e.created_at) AS month,
    p.name AS provider_name,
    m.display_name AS model_name,
    SUM(e.ai_cost) AS total_cost,
    SUM(e.tokens_input) AS total_tokens_input,
    SUM(e.tokens_output) AS total_tokens_output,
    COUNT(e.id) AS total_evaluations
FROM public.evaluations e
JOIN public.ai_evaluation_configs aec ON e.ai_config_id = aec.id
JOIN public.ai_models m ON aec.model_id = m.id
JOIN public.ai_providers p ON m.provider_id = p.id
GROUP BY month, provider_name, model_name;
