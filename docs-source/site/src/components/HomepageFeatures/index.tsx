import type {ReactNode} from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  Svg: React.ComponentType<React.ComponentProps<'svg'>>;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'Build Enterprise-Ready Microservices Fast',
    Svg: require('@site/static/img/logo.svg').default,
    description: (
      <>
        Simplify development and deployment of secure Spring Boot and Helidon microservices with built-in Oracle Database support—ready for multi-cloud environments and production use.
      </>
    ),
  },
  {
    title: 'AI-Driven Backend as a Service',
    Svg: require('@site/static/img/logo.svg').default,
    description: (
      <>
        Empower your applications with advanced AI, real-time messaging, and automated observability—integrated APIs, gateways, and enterprise infrastructure out of the box.
      </>
    ),
  },
  {
    title: 'Simple DevOps Experience',
    Svg: require('@site/static/img/logo.svg').default,
    description: (
      <>
        Accelerate project delivery with out-of-the-box service discovery, monitoring, and transactional consistency for modern microservices architectures.
      </>
    ),
  },
];

function Feature({title, Svg, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Svg
          className={styles.featureSvg}
          aria-hidden="true"
          focusable="false"
        />
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
